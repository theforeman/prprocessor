require 'rake'
require 'rake/testtask'

desc 'Test the prprocessor.'
Rake::TestTask.new(:test) do |t|
  t.libs << '.'
  t.test_files = FileList['test/**/*_test.rb']
  t.verbose = true
  t.ruby_opts = ["-W1"]
end

task :default => [:test]
