#!/usr/local/bin/ruby
require 'wikk_configuration'
CONF_FILE = "#{ARGV[0]}"
RLIB = '../rlib'

require_relative "#{RLIB}/wikk_conf.rb"
require_relative "#{RLIB}/monitor/lastseen_sql.rb"

def cluster_hosts_url(hosts)
  s = ''
  hosts.each { |h| s << "host=#{h}&" }
  return s
end

def graph_cluster(cluster_name, hosts, status)
  filename = cluster_name.gsub( /\s+/, '_')
  cluster_node_name = cluster_name.gsub(/\s+/, '\\n')

  File.open("#{TMP_PLOT_DIR}/#{filename}.dot", 'w') do |fd|
    fd.print <<~GNUPLOT
      graph #{filename} {
        graph [ fontname = "Times", fontsize=12, dpi=72  ];
        node [shape=ellipse, fontname = "Lucida", fontsize=12];
          \"#{cluster_node_name}\" [color=#{(color = status[cluster_name]) ? color : 'black'}, URL="/admin/ping.html?host=#{filename.downcase.sub('_clients', '')}&traffic=#{filename.downcase.sub('_clients', '')}&#{cluster_hosts_url(hosts)}hour=1&no_traffic=true"];
        node [shape=house, color=black, fontname = "Lucida", fontsize=12];
    GNUPLOT

    hosts.each { |h| fd.print("\t#{h} [ color=#{(color = status[h]) ? color : 'black'}, URL=\"/admin/ping.html?host=#{h}&hour=1#{status[h] == 'green' ? '' : '&lastseen=true'}\"];\n" ) }
    fd.print "\n"

    hosts.each_with_index do |c, i|
      if i.odd? # balancing the graph by having half the hosts above, and half below the cluster node.
        fd.print("\"#{cluster_node_name}\" -- #{c} [fontname = \"Lucida\", fontsize=12, color=#{(color = status[c]) ? color  : 'black'}, len=1.50 ];\n" )
      else
        fd.print("#{c} -- \"#{cluster_node_name}\" [fontname = \"Lucida\", fontsize=12, color=#{(color = status[c]) ? color  : 'black'}, len=1.50 ];\n" )
      end
    end
    fd.print "}\n"
  end

  system("#{NEATO} -Tpng -o #{STATUS_WWW_DIR}/#{filename}.png -Tcmapx -o #{STATUS_WWW_DIR}/#{filename}_map.html #{TMP_PLOT_DIR}/#{filename}.dot")
end

def text_status(clusters, status, filename)
  File.open(filename, 'w') do |fd|
    fd.print <<~HTML
      <html>
      <head><title>Offline Routers</title></head>
      <body>
        <h1>Offline</h1>
          <span style="FONT-FAMILY:Arial ; font-size: 10px; margin-top:0; margin-left:0;" >#{Time.now}</span>
          <p>
    HTML
    clusters.each do |cluster_name, hosts|
      next unless (s = status[cluster_name]) != 'green' && s != 'black'

      fd.print <<~HTML
        #{cluster_name}
        <ul>
      HTML
      hosts.each do |h|
        fd.print <<~HTML if status[h] != 'green'
          <li><a href=\"/admin/ping.html?host=#{h}&hour=1&lastseen=true\"><span style=\"color:#{status[h]}\">#{h}</span></a></li>
        HTML
      end
      fd.print <<~HTML
        </ul>
      HTML
    end
    fd.print <<~HTML
      </body>
      </html>
    HTML
  end
end

@mysql_conf = WIKK::Configuration.new(MYSQL_CONF)

lastseen = Lastseen.new(@mysql_conf) # ("ntm_admin", "ljaffle_ntm", "admin2.wikarekare.org", "ntm")
status = lastseen.global_state

lastseen.clusters.each do |cluster, hosts|
  graph_cluster(cluster, hosts, status)
end

text_status(lastseen.clusters, status, "#{STATUS_WWW_DIR}/offline.html")
