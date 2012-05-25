require File.join(File.dirname(__FILE__), 'rails_project.rb')
module Maven
  module Tools
    class PomGenerator
      def read_rails(filename, plugin_version = nil, jruby_version = nil)
        proj = Maven::Tools::RailsProject.new
        proj.load_gemfile(filename.to_s)
        proj.load_jarfile(File.join(File.dirname(filename.to_s), 'Jarfile'))
        proj.load_mavenfile(File.join(File.dirname(filename.to_s), 'Mavenfile'))
        proj.add_defaults(versions(plugin_version, jruby_version))
        proj.to_xml
      end

      # the dummy allows to have all three methods the same argument list
      def read_gemfile(filename, plugin_version = nil, dummy = nil)
        dir = File.dirname(filename)
        proj = 
          if File.exists? File.join( dir, 'config', 'application.rb' )
            Maven::Tools::RailsProject.new
          else
            Maven::Tools::GemProject.new
          end
        proj.load_gemfile(filename.to_s)
        proj.load_jarfile(File.join(File.dirname(filename.to_s), 'Jarfile'))
        proj.load_mavenfile(File.join(File.dirname(filename.to_s), 'Mavenfile'))
        proj.add_defaults(versions(plugin_version, nil))
        proj.to_xml
      end

      # the dummy allows to have all three methods the same argument list
      def read_gemspec(filename, plugin_version = nil, dummy = nil)
        proj = Maven::Tools::GemProject.new
        proj.load_gemspec(filename.to_s)
        proj.load_jarfile(File.join(File.dirname(filename.to_s), 'Jarfile'))
        proj.load_mavenfile(File.join(File.dirname(filename.to_s), 'Mavenfile'))
        proj.add_defaults(versions(plugin_version, nil))
        proj.to_xml
      end

      private

      def versions(plugin_version, jruby_version)
        result = {}
        result[:jruby_plugins] = plugin_version if plugin_version
        result[:jruby_version] = jruby_version if jruby_version
        result
      end
    end
  end
end

generator = Maven::Tools::PomGenerator.new

case ARGV.size
when 2
  puts generator.send("read_#{ARGV[0]}".to_sym, ARGV[1])
when 3
  puts generator.send("read_#{ARGV[0]}".to_sym, ARGV[1], ARGV[2])
when 4
  puts generator.send("read_#{ARGV[0]}".to_sym, ARGV[1], ARGV[2], ARGV[3])
else
  generator
end
