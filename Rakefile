require "rake/testtask"
require 'rubygems/package_task'
load 'minus5_mssql.gemspec'

task :default => [:test]

Rake::TestTask.new do |test|
  test.libs << "test"
  test.test_files = Dir[ "test/test_*.rb" ]
  test.verbose = true
end

Gem::PackageTask.new(GEMSPEC) do |pkg|
end

gem_file = "pkg/minus5_mssql-#{GEMSPEC.version}.gem"

desc "build gem and deploy to gems.minus5.hr"
task :deploy => [:gem] do
  print "copying to korana.s.minus5.hr\n"
  `scp #{gem_file} korana.s.minus5.hr:/var/www/gems.minus5.hr/gems`
  print "updating gem server index\n"
  `ssh korana.s.minus5.hr "cd /var/www/gems.minus5.hr; sudo gem generate_index"`
end
