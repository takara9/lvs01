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

real_servers = node["real_servers"]
vip_ipaddr   = node["vip"]["address"]
vip_netmask  = node["vip"]["netmask"]
vip_portno   = node["vip"]["portno"]
node_state   = node["keepalived"]["state"]

file "/etc/keepalived/keepalived.conf" do
  owner "root"
  group "root"
  mode 0644
  config_file = "! Configuration File for keepalived\n"\
"\n" \
"vrrp_instance VI_1 {\n" \
"    state #{node_state}\n" \
"    interface eth1\n" \
"    lvs_sync_daemon_interface eth0\n" \
"    virtual_router_id 51\n" \
"    priority 150\n" \
"    advert_int 1\n" \
"    authentication {\n" \
"        auth_type PASS\n" \
"        auth_pass grr02\n" \
"    }\n" \
"    virtual_ipaddress {\n" \
"        #{vip_ipaddr}\n" \
"    }\n" \
"}\n" \
"virtual_server #{vip_ipaddr} #{vip_portno} {\n" \
"    delay_loop 20\n" \
"    lb_algo rr\n" \
"    lb_kind DR\n" \
"    persistence_timeout 50\n" \
"    protocol TCP\n"

  real_servers.each do |ipaddr,port|
    config_file = "#{config_file}" \
"    real_server #{ipaddr} #{port} {\n"\
"        weight 1\n" \
"        TCP_CHECK {\n" \
"            connect_timeout 3\n" \
"        }\n" \
"    }\n"
  end
  content "#{config_file}}\n"
  action :create
  notifies :restart, "service[keepalived]"
end
