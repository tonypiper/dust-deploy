class Nginx < Recipe
  desc 'nginx:deploy', 'installs and configures nginx web server'
  def deploy
    # abort if nginx cannot be installed
    return unless @node.install_package 'nginx'

    @node.scp "#{@template_path}/nginx.conf", '/etc/nginx/nginx.conf'

    # remove old sites that may be present
    ::Dust.print_msg 'deleting old sites in /etc/nginx/sites-*'
    @node.rm '/etc/nginx/sites-*/*', :quiet => true
    ::Dust.print_ok

    @config.each do |state, sites|
      sites.to_array.each do |site|
        @node.deploy_file "#{@template_path}/sites/#{site}", "/etc/nginx/sites-available/#{site}", :binding => binding
    
        # symlink to sites-enabled if this is listed as an enabled site
        if state == 'sites-enabled'
          ::Dust.print_msg "enabling #{site}", :indent => 2
          ::Dust.print_result @node.exec("cd /etc/nginx/sites-enabled && ln -s ../sites-available/#{site} #{site}")[:exit_code]
        end
      end
    end

    # check configuration and restart nginx
    ::Dust.print_msg 'checking nginx configuration'
    if @node.exec('/etc/init.d/nginx configtest')[:exit_code] == 0
      ::Dust.print_ok
      @node.restart_service('nginx') if options.restart?
    else
      ::Dust.print_failed
    end
  end
  
  desc 'nginx:status', 'displays nginx status'
  def status
    return unless @node.package_installed? 'nginx'
    @node.print_service_status 'nginx'
  end  
end
