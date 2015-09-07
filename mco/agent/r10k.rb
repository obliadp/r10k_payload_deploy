module MCollective
  module Agent
    class R10k<RPC::Agent
       activate_when do
         #This helper only activate this agent for discovery and execution
         #If r10k is found on $PATH.
         # http://docs.puppetlabs.com/mcollective/simplerpc/agents.html#agent-activation
         r10k_binary = `which r10k 2> /dev/null`
         if r10k_binary == ""
           #r10k not found on path.
           false
         else
           true
         end
       end
       ['status'].each do |act|
          action act do
            validate :path, :shellsafe
            path = request[:path]
            reply.fail "Path not found #{path}" unless File.exists?(path)
            return unless reply.statuscode == 0
            run_cmd act, path
            reply[:path] = path
          end
        end
        ['deploy',
         'deploy_module',
         'deploy_with_modules'].each do |act|
          action act do
            if act == 'deploy' || act == 'deploy_with_modules'
              validate :environment, :shellsafe
              environment = request[:environment]
              run_cmd act, environment
              reply[:environment] = environment
            elsif act == 'deploy_module'
              validate :module_name, :shellsafe
              module_name = request[:module_name]
              run_cmd act, module_name
              reply[:module_name] = module_name
            else
              run_cmd act
            end
          end
        end
      private

      def cmd_as_user(cmd, cwd = nil)
        if /^\w+$/.match(request[:user])
          cmd_as_user = ['su', '-', request[:user], '-c', '\''] 
          if cwd
            cmd_as_user += ['cd', cwd, '&&']
          end
          cmd_as_user += cmd + ["'"]
          # doesn't seem to execute when passed as an array
          cmd_as_user.join(' ')
        else
          cmd
        end
      end

      def run_cmd(action,arg=nil)
        output = ''
        git  = ['/usr/bin/env', 'git']
        r10k = ['/usr/bin/env', 'r10k']
        # Given most people using this are using Puppet Enterprise, add the PE Path
        environment = {"LC_ALL" => "C","PATH" => "#{ENV['PATH']}:<%= if @is_pe == true or @is_pe == 'true' then '/opt/puppet/bin' else '/usr/local/bin' end %>", "http_proxy" => "<%= @http_proxy %>", "https_proxy" => "<%= @http_proxy %>", "GIT_SSL_NO_VERIFY" => "<%= @git_ssl_no_verify %>" }
        case action
          when 'status'
            cmd = 'git status'
            reply[:status] = run(cmd_as_user(cmd, arg), :stderr => :error, :stdout => :output, :chomp => true, :cwd => arg, :environment => environment )
          when 'deploy', 'deploy_module', 'deploy_with_modules'
            cmd = r10k
            if action == 'deploy'
              cmd << 'deploy' << 'environment' << arg
            elsif action == 'deploy_with_modules'
              cmd << 'deploy' << 'environment' << arg << '-p'
            elsif action == 'deploy_module'
              cmd << 'deploy' << 'module' << arg
            end
            reply[:status] = run(cmd_as_user(cmd), :stderr => :error, :stdout => :output, :chomp => true, :environment => environment)
        end
      end
    end
  end
end
