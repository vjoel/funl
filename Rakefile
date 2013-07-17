require 'rake'
require 'rake/testtask'

def version
  require 'funl/version'
  @version ||= Funl::VERSION
end

prj = "funl"

desc "Run tests"
Rake::TestTask.new :test do |t|
  t.libs << "lib"
  t.libs << "ext"
  t.test_files = FileList["test/**/*.rb"]
end

desc "commit, tag, and push repo; build and push gem"
task :release do
  tag = "#{prj}-#{version}"

  sh "gem build #{prj}.gemspec"

  sh "git commit -a -m 'release #{version}'"
  sh "git tag #{prj}-#{version}"
  sh "git push"
  sh "git push --tags"
  
  sh "gem push #{prj}-#{version}.gem"
end
