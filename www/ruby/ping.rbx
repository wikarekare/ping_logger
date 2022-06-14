#!/usr/local/ruby3.0/bin/ruby
require 'cgi'
require 'wikk_web_auth'
require 'wikk_configuration'

RLIB = '../../../rlib'
require_relative "#{RLIB}/wikk_conf.rb"
require "#{RLIB}/monitor/lastseen_sql.rb"
require "#{RLIB}/monitor/pinglog.rb"
require "#{RLIB}/monitor/signal_log_new.rb"
require "#{RLIB}/account/graph_sql_traffic.rb"

require 'cgi/session'
require 'cgi/session/pstore'     # provides CGI::Session::PStore

@link = 'false'
@mysql_conf = WIKK::Configuration.new(MYSQL_CONF)

def format_images(images)
  m = 0
  # s = "<table border=\"0\">"
  s = ''
  images.each_line do |l|
    if m == 0
      # s += "<tr>#{l.sub("<p>","<td>").sub("</p>", "</td>").chomp}"
      s += "#{l.sub('<p>', '').sub('</p>', '').chomp}&nbsp;&nbsp;"
      m += 1
    else
      # s += "#{l.sub("<p>","<td>").sub("</p>", "</td>").chomp}</tr>"
      s += "#{l.sub('<p>', '').sub('</p>', '').chomp}<br>"
      m = 0
    end
  end
  # s += "<td>&nbsp;</td></tr>" if m == 1
  # s += "</table>"
  return s
end

def decode
  @cgi = CGI.new('html4Tr')
  @hosts = @cgi.params['host']
  @traffic = @cgi.params['traffic']
  @dist = CGI.escapeHTML(@cgi['dist'])
  @dist_b = CGI.escapeHTML(@cgi['dist_b'])
  @link = CGI.escapeHTML(@cgi['link'])
  @hours = CGI.escapeHTML(@cgi['hours'])
  @days = CGI.escapeHTML(@cgi['days'])
  @endnow = CGI.escapeHTML(@cgi['endnow'])
  @start_date_time = CGI.escapeHTML(@cgi['start'])
  @yesterday = CGI.escapeHTML(@cgi['yesterday'])
  @prev_period = CGI.escapeHTML(@cgi['prev'])
  @next_period = CGI.escapeHTML(@cgi['next'])
  @prev_day = CGI.escapeHTML(@cgi['prevDay'])
  @next_day = CGI.escapeHTML(@cgi['nextDay'])
  @prev_hour = CGI.escapeHTML(@cgi['prevHour'])
  @next_hour = CGI.escapeHTML(@cgi['nextHour'])
  @prev_month = CGI.escapeHTML(@cgi['prevMonth'])
  @this_month = CGI.escapeHTML(@cgi['thisMonth'])
  @next_month = CGI.escapeHTML(@cgi['nextMonth'])
  @last_hour = CGI.escapeHTML(@cgi['lastHour'])
  @last_day = CGI.escapeHTML(@cgi['lastDay'])
  @lastseen = CGI.escapeHTML(@cgi['lastseen'])
  @form_state = CGI.escapeHTML(@cgi['form_on'])
  @no_ping = CGI.escapeHTML(@cgi['noping'])
  @no_traffic = CGI.escapeHTML(@cgi['no_traffic'])
  @signal = @cgi.params['signal']
  @graphtype = CGI.escapeHTML(@cgi['graphtype'])
  @this_graphtype = CGI.escapeHTML(@cgi['this_graphtype'])
  @connections = CGI.escapeHTML(@cgi['connections'])
end

def encode
  encoded = []
  @traffic.each { |s| encoded << "traffic=#{s}" if s != '' }
  @hosts.each { |s| encoded << "host=#{s}" if s != '' }
  @signal.each { |s| encoded << "signal=#{s}"   if s != '' }
  encoded << "connections=#{@connections}" if @connections != ''
  encoded << "graphtype=#{@graphtype}" if @graphtype != ''
  encoded << "no_traffic=#{@no_traffic}" if @no_traffic == 'true'
  encoded << "noping=#{@no_ping}" if @no_ping == 'true'
  encoded << "dist_b=#{@dist}" if @dist
  encoded << "hours=#{@form_hours}"
  encoded << "days=#{@form_days}"
  encoded << "start=#{@start_date_time}" if @start_date_time != ''
  encoded << "form_on=#{@form_on}" if @form_on
  encoded << "link=#{@link}" if @link == 'true'
  if encoded.length > 0
    return '?' + encoded.join('&')
  else
    return ''
  end
end

decode
message = ''

@form_on = (@form_state == 'on' || @form_state == 'true')
auth_needed = ( @form_on || @connections =~ /[PC][0-9]*/ )
@dist = ( @dist_b == 'true' || @dist == 'true')

begin
  @authenticated = WIKK::Web_Auth.authenticated?(@cgi)
rescue Exception => e
  @authenticated = false
end

# don't need to authenticate, or we do, and have.
if auth_needed && !@authenticated
  @form_on = false
  @connections = 'D'
end

if @connections == 'C'
  @graphtype = 'graphC'
elsif @connections == 'C2'
  @graphtype = 'graphC2'
elsif @connections == 'C3'
  @graphtype = 'graphC3'
elsif @connections == 'P'
  @graphtype = 'graphP'
elsif @connections == 'P2'
  @graphtype = 'graphP2'
elsif @connections == 'P3'
  @graphtype = 'graphP3'
elsif @connections == 'T'
  @graphtype = 'grapht'
elsif @connections == 'D'
  @graphtype = 'dualgraph'
elsif @graphtype == '' && @this_graphtype != ''
  @graphtype = @this_graphtype
end

if @graphtype == 'grapht'
  split_in_out = true # actually doesn't matter, as it isn't looked at in this case.
elsif @graphtype == 'dualgraph'
  split_in_out = true
elsif @graphtype == 'singlegraph'
  split_in_out = false
elsif @graphtype == 'graph3d'
  split_in_out = false
elsif @graphtype == 'graphC' || @graphtype == 'graphP' || @graphtype == 'graphP2' || @graphtype == 'graphP3' || @graphtype == 'graphC2' || @graphtype == 'graphC3'
  split_in_out = false
else
  @graphtype = 'dualgraph'
  split_in_out = true
end

if @hosts != nil && @hosts.length > 0
  # not sure why, but 0 length array causes silent exception in @cgi
  # Could be the fastcgi for ruby? It doesn't happen under ruby
  @hosts.collect! { |h| CGI.escapeHTML(h) }
else
  @hosts = [ '' ] # saves a test later
end

if @traffic != nil && @traffic.length > 0
  @traffic.collect! { |h| CGI.escapeHTML(h) }
else
  @traffic = [] # saves a test later
end

begin
  if @signal != nil && @signal.length > 0
    # not sure why, but 0 length array causes silent exception in @cgi
    # Could be the fastcgi for ruby? It doesn't happen under ruby
    @signal.collect! { |h| CGI.escapeHTML(h) }
  else
    @signal = []
  end
rescue Exception => e
  message = e.message
end

if @graphtype == 'grapht' # is @graphtype grapht
  @no_ping = 'true'
  if @this_month == ''
    st = (@start_date_time == '' ? Time.now.start_of_billing : Time.parse(@start_date_time ) )
    if @prev_month != ''
      st = st.prev_month
      @hours = ''
      @days = ''
    elsif @next_month != ''
      st = st.next_month
      @hours = ''
      @days = ''
    end
  else
    st = Time.now.start_of_billing
    @days = 31
    @hours = 0
  end

  @start_date_time = st.to_sql
  start = st.to_i

  if @days != '' || @hours != ''
    if @days != ''
      offset = @hours == '' ? 0 : @hours.to_f
      @hours = @days.to_f * 24 + offset
    elsif @hours == ''
      @hours = 1.0
    else
      @hours = @hours.to_f
    end

    if @hours == 0.0
      @hours = 24.0
    end

    end_time = start + @hours * 3600
  else
    end_time = st.next_month.to_i
    @hours = (end_time - start) / 3600
  end
else
  if @days != ''
    offset = @hours == '' ? 0 : @hours.to_f
    @hours = @days.to_f * 24 + offset
  elsif @hours == ''
    @hours = 1.0
  else
    @hours = @hours.to_f
  end

  if @hours == 0.0
    @hours = 1.0
  end

  if @endnow != ''
    start = Time.now.to_i - (@hours * 60 * 60).to_i
  elsif @lastseen != ''
    lastseen_record = Lastseen.new(@mysql_conf)
    start = if (d = lastseen_record.find(@hosts[0])).nil?
              Time.now.to_i - (@hours * 60 * 60).to_i
            else
              d.to_i - (@hours * 60 * 60).to_i / 2
            end
  elsif @start_date_time != ''
    start = Time.parse(@start_date_time ).to_i
  else
    start = Time.now.to_i - (@hours * 60 * 60).to_i
  end

  if @prev_hour != ''
    start -= 3600
    @hours = 1.0
    @start_date_time  = Time.at(start).to_sql
  elsif @next_hour != ''
    start += 3600
    @hours = 1.0
    @start_date_time = Time.at(start).to_sql
  elsif @last_hour != ''
    start = Time.now.to_i - 3600
    @hours = 1.0
    @start_date_time = Time.at(start).to_sql
  elsif @prev_day != ''
    start -= 86400
    @hours = 24.0
    @start_date_time = Time.at(start).to_sql
  elsif @next_day != ''
    start += 86400
    @hours = 24.0
    @start_date_time = Time.at(start).to_sql
  elsif @last_day != ''
    start = Time.now.to_i - 86400
    @hours = 24.0
    @start_date_time  = Time.at(start).to_sql
  elsif @prev_period != ''
    start -= (@hours * 60 * 60).to_i
    @start_date_time  = Time.at(start).to_sql
  elsif @next_period != ''
    start += (@hours * 60 * 60).to_i
    @start_date_time  = Time.at(start).to_sql
  elsif @yesterday == '1'
    start -= 86400 # go back a day
    @start_date_time = Time.at(start).to_sql
  end

  end_time = start + (@hours * 60 * 60).to_i
end

images = ''
# message = ""
message << @graphtype

if @no_traffic != 'true' || @traffic.length > 0
  if @traffic.length > 0
    @hold = @hosts
    @hosts = @traffic
  end
  begin
    if @graphtype == 'grapht'
      images = if @hosts[0] == '' || @hosts[0] == 'all'
                 Graph_Total_Usage.new(@mysql_conf, nil, Time.at(start), Time.at(end_time)).images
               else
                 Graph_Host_Usage.new(@mysql_conf, @hosts[0], Time.at(start), Time.at(end_time)).images
               end
    elsif @graphtype == 'graph3d'
      if @hosts[0] == '' || @hosts[0] == 'www.orcon.net.nz' || @hosts[0] == 'wikk-b09' || @hosts[0] == 'wikk-b13' || @hosts[0] == 'all'
        images = Graph_3D.new(@mysql_conf, 'all', @dist, Time.at(start), Time.at(end_time) ).images
      else
        g = Graph_3D.graph_parent(@mysql_conf, @hosts[0], @dist, Time.at(start), Time.at(end_time) )
        images = g.images
        @hosts = g.hosts
      end
    elsif @graphtype == 'graphC'
      images += if @hosts[0] =~ /wikk[0-9][0-9][0-9]/
                  Graph_Connections.new(@hosts[0] + '-net', Time.at(start), Time.at(end_time)).images
                else
                  Graph_Connections.new(@hosts[0], Time.at(start), Time.at(end_time)).images
                end
    elsif @graphtype == 'graphP'
      images += if @hosts[0] =~ /wikk[0-9][0-9][0-9]/
                  Graph_Ports.new(@hosts[0] + '-net', Time.at(start), Time.at(end_time)).images
                else
                  Graph_Ports.new(@hosts[0], Time.at(start), Time.at(end_time)).images
                end
      #
    elsif @graphtype == 'graphP2' # Port Hist
      images += if @hosts[0] =~ /wikk[0-9][0-9][0-9]/
                  Graph_Ports_Hist.new(@hosts[0] + '-net', Time.at(start), Time.at(end_time)).images
                else
                  Graph_Ports_Hist.new(@hosts[0], Time.at(start), Time.at(end_time)).images
                end
    elsif @graphtype == 'graphP3' # Port Hist
      images += if @hosts[0] =~ /wikk[0-9][0-9][0-9]/
                  Graph_Ports_Hist_trim.new(@hosts[0] + '-net', Time.at(start), Time.at(end_time)).images
                else
                  Graph_Ports_Hist_trim.new(@hosts[0], Time.at(start), Time.at(end_time)).images
                end
    elsif @graphtype == 'graphC2' # Hosts hist
      images += if @hosts[0] =~ /wikk[0-9][0-9][0-9]/
                  Graph_Host_Hist.new(@hosts[0] + '-net', Time.at(start), Time.at(end_time)).images
                else
                  Graph_Host_Hist.new(@hosts[0], Time.at(start), Time.at(end_time)).images
                end
    elsif @graphtype == 'graphC3' # Hosts hist trim
      images += if @hosts[0] =~ /wikk[0-9][0-9][0-9]/
                  Graph_Host_Hist_trim.new(@hosts[0] + '-net', Time.at(start), Time.at(end_time)).images
                else
                  Graph_Host_Hist_trim.new(@hosts[0], Time.at(start), Time.at(end_time)).images
                end
    elsif @dist
      if @hosts[0] == 'all'
        images += Graph_2D.graph_all(@mysql_conf, split_in_out, Time.at(start), Time.at(end_time) )
      else
        images = Graph_2D.new(@mysql_conf, @hosts[0], split_in_out, Time.at(start), Time.at(end_time)).images
        images += Graph_2D.graph_clients(@mysql_conf, @hosts[0], split_in_out, Time.at(start), Time.at(end_time) )
      end
    elsif @link == 'true' && @hosts[0] =~ /^link[1-7]/
      images = Graph_2D.new(@mysql_conf, @hosts[0], split_in_out, Time.at(start), Time.at(end_time)).images
      images += Graph_2D.graph_link(@mysql_conf, @hosts[0], split_in_out, Time.at(start), Time.at(end_time) )
    elsif @hosts[0] == 'external1'
      images = Graph_2D.new(@mysql_conf, 'link1', split_in_out, Time.at(start), Time.at(end_time) ).images
    elsif @hosts[0] == 'external2'
      images = Graph_2D.new(@mysql_conf, 'link2', split_in_out, Time.at(start), Time.at(end_time) ).images
    elsif @hosts[0] == 'external3'
      images = Graph_2D.new(@mysql_conf, 'link3', split_in_out, Time.at(start), Time.at(end_time) ).images
    elsif @hosts[0] == 'external4'
      images = Graph_2D.new(@mysql_conf, 'link4', split_in_out, Time.at(start), Time.at(end_time) ).images
    elsif @hosts[0] == 'external5'
      images = Graph_2D.new(@mysql_conf, 'link5', split_in_out, Time.at(start), Time.at(end_time) ).images
    elsif @hosts[0] == 'external6'
      images = Graph_2D.new(@mysql_conf, 'link6', split_in_out, Time.at(start), Time.at(end_time) ).images
    elsif @hosts[0] == 'external7'
      images = Graph_2D.new(@mysql_conf, 'link7', split_in_out, Time.at(start), Time.at(end_time) ).images
    elsif @hosts[0] == 'www.orcon.net.nz' || @hosts[0] == 'wikk-b09' || @hosts[0] == 'wikk-b13' || @hosts[0] == 'all'
      images = Graph_2D.graph_border(@mysql_conf, split_in_out, Time.at(start), Time.at(end_time) )
    else
      images = Graph_2D.new(@mysql_conf, @hosts[0], split_in_out, Time.at(start), Time.at(end_time) ).images
    end
  rescue Exception => e
    message << e.to_s
  end
  if @traffic.length > 0
    @hosts = @hold
  end
end

@form_days = (@hours / 24).to_i
@form_hours = @hours - (@form_days * 24)
script = <<-EOF
  <script type="text/javascript">
    function correct_form_on(the_form)
    {
      the_form.form_on.value = "#{@form_on == true ? 'off' : (@authenticated ? 'on' : 'off')}";
      the_form.submit();
    }
  </script>
EOF

@traffic_list = ''
@traffic.each { |t| @traffic_list << "<input type=\"hidden\" name=\"traffic\" value=\"#{t}\" id=\"traffic\">\n" }

auth_image = @authenticated ? '/images/unlocked.gif' : '/images/locked.gif'

@cgi.header('type' => 'text/html')
@cgi.out do
  @cgi.html do
    if @hosts.nil? || @hosts.length == 0
      @cgi.head { @cgi.title { 'Ping Graph Error' } + "<META HTTP-EQUIV=\"Pragma\" CONTENT=\"no-cache\">\n" + '<META NAME="ROBOTS" CONTENT="NOINDEX, NOFOLLOW">' } + script +
        @cgi.body { '<b>Error:</b> No host specified<p>' }
    else
      @cgi.head do
        @cgi.title { "#{@hosts.join(',')} Pings" } + script +
          "<META HTTP-EQUIV=\"Pragma\" CONTENT=\"no-cache\">\n" +
          '<META NAME="ROBOTS" CONTENT="NOINDEX, NOFOLLOW">'
      end +
        @cgi.body do
          begin
            host_list = ''
            @hosts.each do |h|
              if @no_ping != 'true'
                ping_record = Ping.new(@mysql_conf)
                if (error = ping_record.gnuplot(h, Time.at(start), Time.at(end_time)) ).nil?
                  images << "<p><img src=\"/#{NETSTAT_DIR}/#{h}-p5f.png\"></p>\n"
                end
              end
              host_list << "<input type=\"hidden\" name=\"host\" value=\"#{h}\" id=\"host\">\n"
            end
          rescue Exception => e
            message << e.message
            host_list = ''
          end
          begin
            signal_list = ''
            @signal.each do |h|
              signal_record = Signal_Class.new(@mysql_conf)
              if (error = signal_record.gnuplot(h, Time.at(start), Time.at(end_time)) ).nil?
                images << "<p><img src=\"/#{NETSTAT_DIR}/#{h}-signal.png\"></p>\n"
              else
                message << error.to_s
              end
              signal_list << "<input type=\"hidden\" name=\"signal\" value=\"#{h}\" id=\"signal\">\n"
            end
          rescue Exception => e
            message << e.message
            signal_list = ''
          end
          "\n<!-- Graph failed with message: #{message}  -->\n" +
            "<form name=\"traffic\" id=\"traffic\" method=\"get\" >\n" +
            '<div style="text-align: right; FONT-FAMILY:Arial ; font-size: 10px; margin-top:0; margin-left:0;">' +
            "<input type=\"hidden\" name=\"form_on\" value=\"#{@form_on == true ? 'on' : 'off'}\" id=\"form_on\">\n" +
            "<a href=\"/ruby/login.rbx?#{@authenticated ? 'action=logout&' : ''}ReturnURL='#{CGI.escapeHTML(ENV['SCRIPT_NAME'] + encode)}'\"><img src=\"#{auth_image}\"/></a>" +
            "<input type=\"image\" src=\"#{@form_on == true ? '/images/expandedTriangle.gif' : '/images/closedTriangle.gif'}\"  onclick=\"correct_form_on(this.form)\" />" +

            # "<a href=\"/ruby/ping.rbx?host=#{@hosts[0]}#{@form_on == true ? "&form=off" : "&form=on" }#{@dist ? '&@dist=true' : ''}#{@graphtype == "" ? "" : "&@graphtype=#{@graphtype}"}\" >\n" +
            # "<img  border=0 src=#{@form_on == true ? '/images/expandedTriangle.gif' : '/icons/blank.gif' }></a>" +
            "#{Time.now}</div><br>\n" +
            ( @dist ? "<input type=\"hidden\" name=\"dist\" value=\"true\" id=\"dist\">\n" : '' ) +
            ( @link == 'true' ? "<input type=\"hidden\" name=\"link\" value=\"true\" id=\"link\">\n" : '' ) +
            ( @no_ping == 'true' ? "<input type=\"hidden\" name=\"noping\" value=\"#{@no_ping}\" id=\"noping\">\n" : '' ) +
            (@graphtype == '' ? '' : "<input type=\"hidden\" name=\"this_graphtype\" value=\"#{@graphtype}\">\n" ) +
            (@no_traffic == 'true' ? "<input type=\"hidden\" name=\"no_traffic\" value=\"#{@no_traffic}\">\n" : '' ) +
            if @graphtype == 'grapht'
              "<div style=\"text-align: left; \">\n" +
              if @form_on == true
                if @hosts[0] == ''
                  ''
                else
                  "Site <input type=\"text\" name=\"host\" value=\"#{@hosts[0]}\" id=\"host\" size=\"10\">&nbsp;\n"
                end +
                "Start of Interval <input type=\"text\" name=\"start\" value=\"#{Time.at(start).to_sql}\" id=\"start\">\n" +
                "Days <input type=\"text\" name=\"days\" value=\"#{@form_days}\" id=\"days\" size=\"5\">" +
                "Hours <input type=\"text\" name=\"hours\" value=\"#{@form_hours}\" id=\"hours\" size=\"4\">\n" +
                "<input type=\"submit\" value=\"Submit\" name=\"submit\">&nbsp;&nbsp;\n" +
                "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;\n" +
                "<BUTTON type=\"submit\" value=\"C\" name=\"connections\"> Hosts </BUTTON>\n" +
                "<BUTTON type=\"submit\" value=\"C3\" name=\"connections\"> Host Hist </BUTTON>\n" +
                "<BUTTON type=\"submit\" value=\"P\" name=\"connections\"> Ports </BUTTON>\n" +
                "<BUTTON type=\"submit\" value=\"P3\" name=\"connections\"> Port Hist </BUTTON>\n" +
                "<BUTTON type=\"submit\" value=\"T\" name=\"connections\"> Usage </BUTTON>\n" +
                "<BUTTON type=\"submit\" value=\"D\" name=\"connections\"> Dual </BUTTON>\n" +
                "<p>\n"
              else
                if @hosts[0] == ''
                  ''
                else
                  "<b>#{@hosts[0]}</b>&nbsp;&nbsp;\n" +
                  "<input type=\"hidden\" name=\"host\" value=\"#{@hosts[0]}\" id=\"host\" size=\"10\">\n"
                end +
                "<input type=\"hidden\" name=\"start\" value=\"#{Time.at(start).to_sql}\">\n"
              end +
              "<input type=\"submit\" value=\"<<\" name=\"prevMonth\"> \n" +
              "<input type=\"submit\" value=\"This Month\" name=\"thisMonth\">\n" +
              "<input type=\"submit\" value=\">>\" name=\"nextMonth\"> \n" +
              "</div>\n"
            else
              @traffic_list +
              host_list +
              signal_list +
              if @form_on == true
                "<div style=\"text-align: left; \">\n" +
                "Start Date-time <input type=\"text\" name=\"start\" value=\"#{Time.at(start).to_sql}\" id=\"start\">\n" +
                "Days <input type=\"text\" name=\"days\" value=\"#{@form_days}\" id=\"days\" size=\"5\">" +
                "Hours <input type=\"text\" name=\"hours\" value=\"#{@form_hours}\" id=\"hours\" size=\"4\">\n" +
                "<input type=\"submit\" value=\"Submit\" name=\"submit\">\n" +
                "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;\n" +
                "<BUTTON type=\"submit\" value=\"C\" name=\"connections\"> Hosts </BUTTON>\n" +
                "<BUTTON type=\"submit\" value=\"C3\" name=\"connections\"> Host Hist </BUTTON>\n" +
                "<BUTTON type=\"submit\" value=\"P\" name=\"connections\"> Ports </BUTTON>\n" +
                "<BUTTON type=\"submit\" value=\"P3\" name=\"connections\"> Port Hist </BUTTON>\n" +
                "<BUTTON type=\"submit\" value=\"T\" name=\"connections\"> Usage </BUTTON>\n" +
                "<BUTTON type=\"submit\" value=\"D\" name=\"connections\"> Dual </BUTTON>\n" +
                '<p>' +
                "<input type=\"submit\" value=\"Last Seen\" name=\"lastseen\"> \n" +
                "<input type=\"submit\" value=\"<<\" name=\"prev\"> \n" +
                "<input type=\"submit\" value=\"Last Period\" name=\"endnow\">\n" +
                "<input type=\"submit\" value=\">>\" name=\"next\"> \n" +
                "</div>\n"
              else
                "<div style=\"text-align: center; float:left;\">\n" +
                "<input type=\"submit\" value=\"<<\" name=\"prevDay\"> \n" +
                "<input type=\"submit\" value=\"Last Day\" name=\"lastDay\"> \n" +
                "<input type=\"submit\" value=\">>\" name=\"nextDay\"> \n" +
                '&nbsp;&nbsp;&nbsp;&nbsp;' +
                "<input type=\"submit\" value=\"<<\" name=\"prevHour\"> \n" +
                "<input type=\"submit\" value=\"Last Hour\" name=\"lastHour\"> \n" +
                "<input type=\"submit\" value=\">>\" name=\"nextHour\"> \n" +
                "</div>\n" +
                (@start_date_time == '' ? '' : "<input type=\"hidden\" name=\"start\" value=\"#{@start_date_time}\">\n" ) +
                if @form_hours == 1.0 && @form_days == 0.0
                  (@yesterday == '' ? '' : "<input type=\"hidden\" name=\"yesterday\" value=\"#{@yesterday}\">\n" )
                else
                  "<input type=\"hidden\" name=\"hours\" value=\"#{@form_hours}\" >" +
                  "<input type=\"hidden\" name=\"days\" value=\"#{@form_days}\">\n"
                end
              end
            end +
            "\n" +
            "<div style=\"text-align: right; float:right;\">\n" +
            if @graphtype == 'grapht'
              ''
            elsif @graphtype == 'graph3d'
              "    <BUTTON type=\"submit\" value=\"dualgraph\" name=\"graphtype\"><img src=\"/images/dualgraph.gif\"></BUTTON>\n" +
              "    <BUTTON type=\"submit\" value=\"singlegraph\" name=\"graphtype\"><img src=\"/images/singlegraph.gif\"></BUTTON>\n"
            elsif @graphtype == 'singlegraph'
              "    <BUTTON type=\"submit\" value=\"#{@dist ? 'false' : 'true'}\" name=\"dist_b\"><img src=\"#{@dist ? '/images/expandedTriangle.gif' : '/images/closedTriangle.gif'}\"></BUTTON>\n" +
              "    <BUTTON type=\"submit\" value=\"graph3d\" name=\"graphtype\"><img src=\"/images/graph3d.gif\"></BUTTON>\n" +
              "    <BUTTON type=\"submit\" value=\"dualgraph\" name=\"graphtype\"><img src=\"/images/dualgraph.gif\"></BUTTON>\n"
            else # dual graph
              "    <BUTTON type=\"submit\" value=\"#{@dist ? 'false' : 'true'}\" name=\"dist_b\"><img src=\"#{@dist ? '/images/expandedTriangle.gif' : '/images/closedTriangle.gif'}\"></BUTTON>\n" +
              ( @link == 'true' ? "<input type=\"hidden\" name=\"link\" value=\"true\" id=\"link\">\n" : '' ) +
              "    <BUTTON type=\"submit\" value=\"graph3d\" name=\"graphtype\"><img src=\"/images/graph3d.gif\"></BUTTON>\n" +
              "    <BUTTON type=\"submit\" value=\"singlegraph\" name=\"graphtype\"><img src=\"/images/singlegraph.gif\"></BUTTON>\n"
            end +
            "</div><br>\n" +
            '</p>' +
            "</form>\n" + format_images(images)
        end
    end
  end
end
