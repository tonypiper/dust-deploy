class Iptables < Thor
  desc 'iptables:deploy', 'configures iptables firewall'
  def deploy node, rules, options
    template_path = "./templates/#{ File.basename(__FILE__).chomp( File.extname(__FILE__) ) }"

    # install iptables
    if node.uses_apt? true or node.uses_emerge? true
      node.install_package 'iptables'

    elsif node.uses_rpm? true
      node.install_package 'iptables-ipv6'

    else
      ::Dust.print_failed 'os not supported'
      return 
    end


    [ 'iptables', 'ip6tables' ].each do |iptables|
      ipv4 = iptables == 'iptables'
      ipv6 = iptables == 'ip6tables'

      ::Dust.print_msg "configuring and deploying ipv4 rules\n" if ipv4
      ::Dust.print_msg "configuring and deploying ipv6 rules\n" if ipv6

      iptables_script = '' 

      # default policy for chains
      if node.uses_apt? true or node.uses_emerge? true
        iptables_script += "-P INPUT DROP\n" +
                     "-P OUTPUT DROP\n" +
                     "-P FORWARD DROP\n" +
                     "-F\n"
        iptables_script += "-F -t nat\n" if ipv4
        iptables_script += "-X\n"

      elsif node.uses_rpm? true
        iptables_script += "*filter\n" +
                     ":INPUT DROP [0:0]\n" +
                     ":FORWARD DROP [0:0]\n" +
                     ":OUTPUT DROP [0:0]\n"
      end

      # allow localhost
      iptables_script += "-A INPUT -i lo -j ACCEPT\n"

      # drop invalid packets
      iptables_script += "-A INPUT -m state --state INVALID -j DROP\n"

      # allow related packets
      iptables_script += "-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT\n"

      # drop tcp packets with the syn bit set if the tcp connection is already established
      iptables_script += "-A INPUT -p tcp --tcp-flags SYN SYN -m state --state ESTABLISHED -j DROP\n" # if ipv4

      # drop icmp timestamps
      iptables_script += "-A INPUT -p icmp --icmp-type timestamp-request -j DROP\n" if ipv4
      iptables_script += "-A INPUT -p icmp --icmp-type timestamp-reply -j DROP\n" if ipv4

      # allow other icmp packets
      iptables_script += "-A INPUT -p icmpv6 -j ACCEPT\n" if ipv6
      iptables_script += "-A INPUT -p icmp -j ACCEPT\n"


      # drop invalid outgoing packets
      iptables_script += "-A OUTPUT -m state --state INVALID -j DROP\n"

      # allow related outgoing packets
      iptables_script += "-A OUTPUT -m state --state RELATED,ESTABLISHED -j ACCEPT\n"


      # map rules to iptables strings
      rules.each do |chain, chain_rules|
        chain_rules.each do |rule|

          # set default variables

          rule['ip-version'] ||= [4, 6]
          rule['jump'] ||= ['ACCEPT']

          # we're going to need a protocol, if we want to use ports, defaulting to tcp
          rule['protocol'] ||= ['tcp'] if rule['dport'] or rule['sport']

          # convert non-array variables to array, so we won't get hickups when using .each and .combine
          rule.each { |k, v| rule[k] = [ rule[k] ] if rule[k].class != Array }

          next unless rule['ip-version'].include? 4 if ipv4
          next unless rule['ip-version'].include? 6 if ipv6

          parse_rule(rule).each do |r|
            # TODO: parse nicer output
            ::Dust.print_msg "adding rule: '#{r.join ' ' }'\n", 2
            iptables_script += "-A #{chain.upcase} #{r.join ' '}\n"
          end
        end
      end

      # deny the rest incoming
      iptables_script += "-A INPUT -p tcp -j REJECT --reject-with tcp-reset\n"
      iptables_script += "-A INPUT -j REJECT --reject-with icmp-port-unreachable\n" if ipv4

      # allow everything out
      iptables_script += "-A OUTPUT -j ACCEPT\n"

      # put commit statement for rpm machines
      iptables_script += "COMMIT\n" if node.uses_rpm? true

      # prepend iptables command on non-centos-like machines
      iptables_script = iptables_script.map { |s| "#{iptables} #{s}" }.to_s if node.uses_apt? true or node.uses_emerge? true

      # set header
      header  = ''
      header  = "#!/bin/sh\n" if node.uses_apt? true or node.uses_emerge? true
      header += "# automatically generated by dust\n\n"
      iptables_script = header + iptables_script

      # set the target file depending on distribution
      target = "/etc/network/if-pre-up.d/#{iptables}" if node.uses_apt? true
      target = "/etc/#{iptables}" if node.uses_emerge? true
      target = "/etc/sysconfig/#{iptables}" if node.uses_rpm? true

#puts iptables_script
#      node.write target, iptables_script, true
#
#      node.chmod '700', target if node.uses_apt? true or node.uses_emerge? true
#      node.chmod '600', target if node.uses_rpm? true

      if options.restart?
        ::Dust.print_msg 'applying ipv4 rules' if ipv4
        ::Dust.print_msg 'applying ipv6 rules' if ipv6

        if node.uses_rpm? true
          ::Dust.print_result node.exec("/etc/init.d/#{iptables} restart")[:exit_code]

        elsif node.uses_apt? true or node.uses_emerge? true
          ret = node.exec target
          ::Dust.print_result( (ret[:exit_code] == 0 and ret[:stdout].empty? and ret[:stderr].empty?) )
        end
      end

      # on gentoo, rules have to be saved using the init script,
      # otherwise they won't get re-applied on next startup
      if node.uses_emerge? true
        ::Dust.print_msg 'saving ipv4 rules' if ipv4
        ::Dust.print_msg 'saving ipv6 rules' if ipv6
        ::Dust.print_result node.exec("/etc/init.d/#{iptables} save")[:exit_code]
      end

      puts
    end
  end


  private 

  # map iptables options
  def parse_rule r
    with_dashes = {}
    result = []
    r.each do |k, v|
      # skip ip-version, since its not iptables option
      with_dashes[k] = r[k].map { |value| "--#{k} #{value}" } unless k == 'ip-version'
    end
    with_dashes.values.each { |a| result = result.combine a }
    result
  end
end

