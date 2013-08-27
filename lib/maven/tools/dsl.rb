require 'fileutils'
require 'maven/tools/gemspec_dependencies'
require 'maven/tools/artifact'
require 'maven/tools/jarfile'
require 'maven/tools/versions'

module Maven
  module Tools
    module DSL

      def tesla( &block )
        @model = Model.new
        @model.model_version = '4.0.0'
        @model.name = File.basename( File.expand_path( '.' ) )
        @model.group_id = 'dummy'
        @model.artifact_id = model.name
        @model.version = '0.0.0'
        @context = :project
        nested_block( :project, @model, block ) if block
        result = @model
        @context = nil
        @model = nil
        result
      end
      alias :maven :tesla
      
      def model
        @model
      end

      def eval_pom( src, reference_file = '.' )
        @source = reference_file
        eval( src )
      ensure
        @source = nil
        @basedir = nil
      end

      def basedir( basedir = nil )
        @basedir ||= basedir if basedir
        @basedir ||= File.directory?( @source ) ? @source : 
          File.dirname( @source ) if @source
        @basedir ||= File.expand_path( '.' )
      end

      def artifact( a )
        if a.is_a?( String )
          a = Maven::Tools::Artifact.new( *a.split( /:/ ) )
        end
        self.send a[:type].to_sym, a
      end

      def source(*args)
        warn "ignore source #{args}" if !(args[0].to_s =~ /^https?:\/\/rubygems.org/) && args[0] != :rubygems
      end

      def ruby( *args )
        # ignore
      end

      def path( *args )
        warn 'path block not implemented'
      end

      def git( *args )
        warn 'git block not implemented'
      end

      def is_jruby_platform( *args )
        args.detect { |a| :jruby == a.to_sym }
      end
      private :is_jruby_platform

      def platforms( *args )
        if is_jruby_platform( *args )
          yield
        end
      end

      def group( *args )
        yield
      end

      def gemfile( name = 'Gemfile', options = {} )
        if name.is_a? Hash
          options = name
          name = 'Gemfile'
        end
        name = File.join( basedir, name )

        @gemfile_options = options
        FileUtils.cd( basedir ) do
          eval( File.read( File.expand_path( name ) ) )
        end

        if @gemfile_options
          @gemfile_options = nil
          setup_gem_support( options )
        end
      end

      def setup_gem_support( options, spec = nil, config = {} )
        if spec.nil?
          require_path = '.'
          name = File.basename( File.expand_path( '.' ) )
        else
          require_path = spec.require_path
          name = spec.name
        end
        
        unless model.repositories.detect { |r| r.id == 'rubygems-releases' }
          repository( 'http://rubygems-proxy.torquebox.org/releases',
                      :id => 'rubygems-releases' )
        end

        properties( 'jruby.plugins.version' => '1.0.0-beta-1-SNAPSHOT' )

        if options.key?( :jar ) || options.key?( 'jar' )
          jarpath = options[ :jar ] || options[ 'jar' ]
          if jarpath
            jar = File.basename( jarpath ).sub( /.jar$/, '' )
            output = "#{require_path}/#{jarpath.sub( /#{jar}/, '' )}".sub( /\/$/, '' )
          end
        else
          jar = "#{name}"
          output = "#{require_path}"
        end
        if options.key?( :source ) || options.key?( 'source' )
          source = options[ :source ] || options[ 'source' ]
          build do
            source_directory source
          end
        end
        if jar && ( source || 
                    File.exists?( File.join( basedir, 'src', 'main', 'java' ) ) )
          plugin( :jar, VERSIONS[ :jar_plugin ],
                  :outputDirectory => output,
                  :finalName => jar ) do
            execute_goals :jar, :phase => 'prepare-package'
          end
          plugin( :clean, VERSIONS[ :clean_plugin ],
                  :filesets => [ { :directory => output,
                                   :includes => [ "#{jar}.jar" ] } ] )
        end
      end
      private :setup_gem_support

      def setup_jruby( jruby, jruby_scope = :provided )
        jruby ||= VERSIONS[ :jruby_version ]
        scope( jruby_scope ) do
          if ( jruby < '1.7' )
            warn 'jruby version below 1.7 uses jruby-complete'
            jar 'org.jruby:jruby-core', jruby
          elsif ( jruby < '1.7.5' )
            jar 'org.jruby:jruby-core', jruby
          else
            jar 'org.jruby:jruby', jruby
          end
        end
      end
      private :setup_jruby
      
      def jarfile( file = 'Jarfile', options = {} )
        if file.is_a? Hash 
          options = file
          file = 'Jarfile'
        end
        unless file.is_a?( Maven::Tools::Jarfile )
          file = Maven::Tools::Jarfile.new( File.expand_path( file ) )
        end

        if options[ :skip_locked ] or not file.exists_lock?
          file.populate_unlocked do |dsl|
            setup_jruby( dsl.jruby )
            dsl.artifacts.each do |a|
              dependency a
            end
          end
        else
          file.locked.each do |dep|
            artifact( dep )
          end
          file.populate_unlocked do |dsl|
            setup_jruby( dsl.jruby )
            dsl.artifacts.each do |a|
              if a[ :system_path ]
                dependeny a
              end
            end
          end
        end
      end

      def gemspec( name = nil, options = @gemfile_options || {} )
        properties( 'project.build.sourceEncoding' => 'utf-8' )
        build.directory = '${basedir}/pkg'

        @gemfile_options = nil
        if name.is_a? Hash
          options = name
          name = nil
        end
        if name
          name = File.join( basedir, name )
        else name
          gemspecs = Dir[ File.join( basedir, "*.gemspec" ) ]
          raise "more then one gemspec file found" if gemspecs.size > 1
          raise "no gemspec file found" if gemspecs.size == 0
          name = gemspecs.first
        end
        spec = nil
        FileUtils.cd( basedir ) do
          spec = eval( File.read( File.expand_path( name ) ) )
        end

        id "rubygems:#{spec.name}:#{spec.version}"
        name( spec.summary || spec.name )
        description spec.description
        packaging 'gem'
        url spec.homepage

        extension 'de.saumya.mojo:gem-extension:${jruby.plugins.version}'

        setup_gem_support( options, spec )
        
        config = { :gemspec => name.sub( /^#{basedir}\/?/, '' ) }
        if options[ :include_jars ] || options[ 'include_jars' ] 
          config[ :includeDependencies ] = true
        end
        plugin( 'de.saumya.mojo:gem-maven-plugin:${jruby.plugins.version}',
                config )
      
        deps = Maven::Tools::GemspecDependencies.new( spec )
        deps.runtime.each do |d|
          gem d
        end
        unless deps.development.empty?
          scope :test do
            deps.development.each do |d|
              gem d
            end          
          end
        end
        unless deps.java_runtime.empty?
          deps.java_runtime.each do |d|
            dependency Maven::Tools::Artifact.new( *d )
          end
        end
      end

      def build( &block )
        build = @current.build ||= Build.new
        nested_block( :build, build, block ) if block
        build
      end

      def project( name, url = nil, &block )
        raise 'mixed up hierachy' unless @current == model
        @current.name = name
        @current.url = url

        nested_block(:project, @current, block)
      end

      def id(*value)
        value = value.join( ':' )
        if @context == :project
          fill_gav(@current, value)
          reduce_id
        else
          @current.id = value
        end
      end

      def site( url = nil, options = {} )
        site = Site.new
        fill_options( site, url, options )
        @current.site = site
      end

      def source_control( url = nil, options = {} )
        scm = Scm.new
        fill_options( scm, url, options )
        @current.scm = scm
      end
      alias :scm :source_control

      def issue_management( url, system = nil )
        issues = IssueManagement.new
        issues.url = url
        issues.system = system
        @current.issue_management = issues
      end

      def mailing_list( name = nil, &block )
        list = MailingList.new
        list.name = name
        nested_block( :mailing_list, list, block )
        @current.mailing_lists <<  list
      end

      def archives( *archives )
        @current.archive = archives.shift
        @current.other_archives = archives
      end

      def developer( id = nil, &block )
        dev = Developer.new
        dev.id = id
        nested_block( :developer, dev, block )
        @current.developers <<  dev
      end

      def roles( *roles )
        @current.roles = roles
      end

      def property( options )
        prop = ActivationProperty.new
        prop.name = options[ :name ] || options[ 'name' ]
        prop.value = options[ :value ] || options[ 'value' ]
        @current.property = prop
      end

      def file( options )
        file = ActivationFile.new
        file.missing = options[ :missing ] || options[ 'missing' ]
        file.exists = options[ :exists ] || options[ 'exists' ]
        @current.file = file
      end

      def activation( &block )
        activation = Activation.new
        nested_block( :activation, activation, block )
        @current.activation = activation
      end

      def distribution( &block )
        dist = DistributionManagement.new
        nested_block( :distribution, dist, block )
        @current.distribution_management = dist
      end

      def includes( *items )
        @current.includes = items.flatten
      end

      def excludes( *items )
        @current.excludes = items.flatten
      end

      def test_resource( &block )
        # strange behaviour when calling specs from Rakefile
        return if @current.nil?
        resource = Resource.new
        nested_block( :resource, resource, block )
        if @context == :project
          ( @current.build ||= Build.new ).test_resources << resource
        else
          @current.test_resources << resource
        end
      end

      def resource( &block )
        resource = Resource.new
        nested_block( :resource, resource, block )
        if @context == :project
          ( @current.build ||= Build.new ).resources << resource
        else
          @current.resources << resource
        end
      end

      def repository( url, options = {}, &block )
        do_repository( :repository=, url, options, block )
      end

      def plugin_repository( url, options = {}, &block )
        do_repository( :plugin, url, options, block )
      end

      def snapshot_repository( url, options = {}, &block )
        do_repository( :snapshot_repository=, url, options, block )
      end

      def releases( config )
        respository_policy( :releases=, config )
      end

      def snapshots( config )
        respository_policy( :snapshots=, config )
      end

      def respository_policy( method, config )
        rp = RepositoryPolicy.new
        case config
        when Hash
          rp.enabled = snapshot[ :enabled ]
          rp.update_policy = snapshot[ :update ]
          rp.checksum_policy = snapshot[ :checksum ]
        when TrueClass
          rp.enabled = true
        when FalseClass
          rp.enabled = false
        else
          rp.enabled = 'true' == config
        end
        @current.send( method, rp )
      end

      def inherit( *value )
        @current.parent = fill_gav( Parent, value.join( ':' ) )
        reduce_id
      end
      alias :parent :inherit

      def properties(props)
        props.each do |k,v|
          @current.properties[k.to_s] = v.to_s
        end
        @current.properties
      end

      def extension( *gav )
        @current.build ||= Build.new
        gav = gav.join( ':' )
        ext = fill_gav( Extension, gav)
        @current.build.extensions << ext
      end

      def plugin( *gav, &block )
        if gav.last.is_a? Hash
          options = gav.last
          gav = gav[ 0..-2 ]
        else
          options = {}
        end
        unless gav.first.match( /:/ )
          gav[ 0 ] = "org.apache.maven.plugins:maven-#{gav.first}-plugin"
        end
        gav = gav.join( ':' )
        plugin = fill_gav( @context == :reporting ? ReportPlugin : Plugin,
                           gav)
        set_config( plugin, options )
        if @current.respond_to? :build
          @current.build ||= Build.new
          if @context == :overrides
            @current.build.plugin_management ||= PluginManagement.new
            @current.build.plugin_management.plugins << plugin
          else
            @current.build.plugins << plugin
          end
        else
          @current.plugins << plugin
        end
        nested_block(:plugin, plugin, block) if block
        plugin
      end

      def overrides(&block)
        nested_block(:overrides, @current, block)
      end

      def execute_goal( goal )
        execute_goals( goal )
      end

      def execute_goals( *goals )
        if goals.last.is_a? Hash
          options = goals.last
          goals = goals[ 0..-2 ]
        else
          options = {}
        end
        exec = Execution.new
        # keep the original default of id
        id = options.delete( :id ) || options.delete( 'id' )
        exec.id = id if id
        if @phase
          if options[ :phase ] || options[ 'phase' ]
            raise 'inside phase block and phase option given'
          end
          exec.phase = @phase
        else
          exec.phase = options.delete( :phase ) || options.delete( 'phase' )
        end
        exec.goals = goals.collect { |g| g.to_s }
        set_config( exec, options )
        @current.executions << exec
        # nested_block(:execution, exec, block) if block
        exec
      end

      def dependency( type, *args )
        if args.empty?
          a = type
          type = a[ :type ]
          options = a
        else
          a = ::Maven::Tools::Artifact.from( type, *args )
        end
        d = fill_gav( Dependency, 
                      a ? a.gav : args.join( ':' ) )
        d.type = type.to_s
        if @context == :overrides
          @current.dependency_management ||= DependencyManagement.new
          @current.dependency_management.dependencies << d
        else
          @current.dependencies << d
        end
        if args.last.is_a?( Hash )
          options = args.last
        end
        if options || @scope
          options ||= {}
          if @scope
            if options[ :scope ] || options[ 'scope' ]
              raise "scope block and scope option given"
            end
            options[ :scope ] = @scope
          end
          exclusions = options.delete( :exclusions ) ||
            options.delete( "exclusions" )
          case exclusions
          when Array
            exclusions.each do |v|
              d.exclusions << fill_gav( Exclusion, v )
            end
          when String
            d.exclusions << fill_gav( Exclusion, exclusions )
          end
          options.each do |k,v|
            d.send( "#{k}=".to_sym, v ) unless d.send( k.to_sym )
          end
        end
        d
      end

      def scope( name )
        @scope = name
        yield
        @scope = nil
      end

      def phase( name )
        @phase = name
        yield
        @phase = nil
      end

      def profile( id, &block )
        profile = Profile.new
        profile.id = id if id
        @current.profiles << profile
        nested_block( :profile, profile, block )
      end

      def report_set( *reports, &block )
        set = ReportSet.new
        case reports.last
        when Hash
          options = reports.last
          reports = reports[ 0..-2 ]
          id = options.delete( :id ) || options.delete( 'id' )
          set.id = id if id
          inherited = options.delete( :inherited ) ||
            options.delete( 'inherited' )
          set.inherited = inherited if inherited
        end
        set_config( set, options )
        set.reports = reports#.to_java
        @current.report_sets << set
      end

      def reporting( &block )
        reporting = Reporting.new
        @current.reporting = reporting
        nested_block( :reporting, reporting, block )
      end

      def gem( *args )
        # in some setup that gem could overload the Kernel gem
        return if @current.nil?
        unless args[ 0 ].match( /:/ )
          args[ 0 ] = "rubygems:#{args[ 0 ] }"
        end
        if args.last.is_a?(Hash)
          options = args.last
          unless options.key?(:git) || options.key?(:path)
            platform = options.delete( :platforms ) || options.delete( 'platforms' )
            #if platform.nil? || is_jruby_platform( platform )
            #  options[ :group_id ] = 'rubygems'
            #  options[ :version ] = '[0,)'
            #end
            dependency( :gem, *args )
          end
        else
          #args = args + [ { :group_id => 'rubygems', :version => '[0,)' } ]
          dependency( :gem, *args )
        end
      end

      def local( path, options = {} )
        path = File.expand_path( path )
        dependency( :jar,
                    Maven::Tools::Artifact.new_local( path, :jar, options ) )
      end

      def method_missing( method, *args, &block )
        if @context
          m = "#{method}=".to_sym
          if @current.respond_to? m
            #p @context
            #p m
            #p args
            begin
              @current.send( m, *args ) 
            rescue ArgumentError
              if @current.respond_to? method
                @current.send( method, *args )
              end
            end
            @current
          else
            if ( args.size > 0 &&
                 args[0].is_a?( String ) &&
                 args[0] =~ /^[${}0-9a-zA-Z._-]+(:[${}0-9a-zA-Z._-]+)+$/ ) ||
                ( args.size == 1 && args[0].is_a?( Hash ) )
              dependency( method, *args )
              # elsif @current.respond_to? method
              #   @current.send( method, *args )
              #   @current
            else
              p @context
              p m
              p args
            end
          end
        else
          super
        end
      end

      def xml( xml )
        raise  'Xpp3DomBuilder.build( java.io.StringReader.new( xml ) )'
      end

      def set_config(  receiver, options )
        receiver.configuration = options
      end

      private

      def do_repository( method, url = nil, options = {}, block = nil )
        if @current.respond_to?( method )
          r = DeploymentRepository.new
        else
          r = Repository.new
        end
        # if config = ( options.delete( :snapshot ) ||
        #               options.delete( 'snapshot' ) )
        #   r.snapshot( repository_policy( config ) )
        # end
        # if config = ( options.delete( :release ) ||
        #               options.delete( 'release' ) )
        #   r.snapshot( repository_policy( config ) )
        # end
        nested_block( :repository, r, block ) if block
        fill_options( r, url, options )
        case method
        when :plugin
          @current.plugin_repositories << r
        else
          if @current.respond_to?( method )
            @current.send method, r
          else
            @current.repositories << r
          end
        end
      end

      def fill_options( receiver, url, options )
        url ||= options.delete( :url ) || options.delete( 'url' )
        options.each do |k,v|
          receiver.send "#{k}=".to_sym, v
        end
        receiver.url = url
      end

      def reduce_id
        if parent = @current.parent
          @current.version = nil if parent.version == @current.version
          @current.group_id = nil if parent.group_id == @current.group_id
        end
      end

      def nested_block(context, receiver, block)
        old_ctx = @context
        old = @current

        @context = context
        @current = receiver

        block.call

        @current = old
        @context = old_ctx
      end

      def fill_gav(receiver, gav)
        if gav
          if receiver.is_a? Class
            receiver = receiver.new
          end
          gav = gav.split(':')
          case gav.size
          when 0
            # do nothing - will be filled later
          when 1
            receiver.artifact_id = gav[0]
          when 2
            receiver.group_id, receiver.artifact_id = gav
          when 3
            receiver.group_id, receiver.artifact_id, receiver.version = gav
          when 4
            receiver.group_id, receiver.artifact_id, receiver.version, receiver.classifier = gav
          else
            raise "can not assign such an array #{gav.inspect}"
          end
        end
        receiver
      end
    end
  end
end
