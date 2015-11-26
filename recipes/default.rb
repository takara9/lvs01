#
# Cookbook Name:: lvs01
# Recipe:: default
#
# Copyright 2015, YOUR_COMPANY_NAME
#
#

execute 'apt-get update' do
  command 'apt-get update'
  ignore_failure true
end

execute 'ufw_for_lvs' do
  command "/usr/sbin/ufw allow from #{node['public_prim_subnet']}"
  ignore_failure true
end

execute 'ufw_for_http' do
  command "/usr/sbin/ufw allow #{node['virtual_portno1']}"
  ignore_failure true
end



%w{
  nmon
  ipvsadm
  keepalived
}.each do |pkgname|
  package "#{pkgname}" do
    action :install
  end
end

service "keepalived" do
  action [ :enable, :start]
end

template "/etc/keepalived/keepalived.conf" do
  source "keepalived.conf.erb"
  owner "root"
  group "root"
  mode 0644
  variables({
    :vip1    => node["virtual_ipaddress1"],
    :vport1  => node["virtual_portno1"],
    :rsv_ip1 => node["real_server_ip_addr1"],
    :rsv_pt1 => node["real_server_port1"],
    :rsv_ip2 => node["real_server_ip_addr2"],
    :rsv_pt2 => node["real_server_port2"],
    :pst_to  => node["persistence_timeout"],
  })
  action :create
  notifies :restart, "service[keepalived]"
end

execute 'sysctl' do
  command '/sbin/sysctl -p'
end

cookbook_file "/etc/sysctl.conf" do
  source 'sysctl.conf'
  owner "root"
  group "root"
  mode 0644
  action :create
  notifies :run, 'execute[sysctl]', :immediately
end
