#-*- mode: ruby -*-

gemspec

jruby_plugin( :minitest, :minispecDirectory =>"spec/*spec.rb" ) do
  execute_goals(:spec)
end

#snapshot_repository :jruby, 'http://ci.jruby.org/snapshots/maven'

# (jruby-1.6.7 produces a lot of yaml errors parsing gemspecs)
properties( 'jruby.versions' => ['1.7.12', '1.7.19', '9.0.0.0.pre2'].join(','),
            'jruby.modes' => ['1.9', '2.0','2.1'].join(','),
            # just lock the versions
            'jruby.version' => '1.7.19' )

distribution_management do
  repository :id => :ossrh, :url => 'https://oss.sonatype.org/service/local/staging/deploy/maven2/'
end

plugin :deploy, '2.8.2' do
  execute_goal :deploy, :phase => :deploy, :id => 'deploy gem to maven central'
end

profile :id => :release do
  properties 'maven.test.skip' => true, 'invoker.skip' => true
  plugin :gpg, '1.5' do
    execute_goal :sign, :id => 'sign artifacts', :phase => :verify
  end
  build do
    default_goal :deploy
  end
end

# vim: syntax=Ruby
