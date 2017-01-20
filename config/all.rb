# pipeline generation configuration

# stuff for each app
pipeline.in_each_app do |app|

  if File.exists? 'Dockerfile' then
    pipeline.add 'docker'
  end

end

# pipeline-wide jobs
if pipeline[:charts].length + pipeline[:runnables].length > 0
  pipeline.add 'deploy'
end
