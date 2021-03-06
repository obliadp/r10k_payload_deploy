class MCollective::Application::R10k<MCollective::Application
  def post_option_parser(configuration)
    if ARGV.length >= 1
      configuration[:command] = ARGV.shift
      case configuration[:command]
      when 'status'
        configuration[:path] = ARGV.shift || docs
      when 'deploy','deploy_with_modules'
        configuration[:environment] = ARGV.shift || docs
      when 'deploy_module'
        configuration[:module_name] = ARGV.shift || docs
      end
  else
      docs
    end
  end

  def docs
    puts "Usage: #{$0} status | deploy | deploy_with_modules | deploy_module"
  end

  def main
    mc = rpcclient("r10k", :chomp => true)
    options = {:path => configuration[:path]} if ['status'].include? configuration[:command]
    options = {:environment => configuration[:environment]} if ['deploy'].include? configuration[:command]
    options = {:environment => configuration[:environment]} if ['deploy_with_modules'].include? configuration[:command]
    options = {:module_name => configuration[:module_name]} if ['deploy_module'].include? configuration[:command]
    mc.send(configuration[:command], options).each do |resp|
      puts "#{resp[:sender]}:"
      if resp[:statuscode] == 0
        responses = resp[:data][:output]
        puts responses if responses and ['status','deploy','deploy_with_modules','deploy_module'].include? configuration[:command]
      else
        puts resp[:statusmsg]
      end
    end
    mc.disconnect
    printrpcstats
  end
end
