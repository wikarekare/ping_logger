#!/usr/local/bin/ruby
require 'cgi'
require 'wikk_web_auth'
require 'wikk_configuration'

load '/wikk/etc/wikk.conf' unless defined? WIKK_CONF
require "#{RLIB}/monitor/lastseen_sql.rb"
require "#{RLIB}/monitor/ping_log.rb"
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

@form_on = @form_state == 'on' || @form_state == 'true'
auth_needed = @form_on || @connections =~ /[PC][0-9]*/
@dist = @dist_b == 'true' || @dist == 'true'

begin
  pstore_conf = JSON.parse(File.read(PSTORE_CONF))
  @authenticated = WIKK::Web_Auth.authenticated?(@cgi, pstore_config: pstore_conf)
rescue Exception => e # rubocop:disable Lint/RescueException
  @authenticated = false
end

# don't need to authenticate, or we do, and have.
if auth_needed && !@authenticated
  @form_on = false
  @connections = 'D'
end

@graphtype = case @connections
             when 'C', 'C2', 'C3', 'P', 'P2', 'P3', 'T'
               @graphtype = "graph#{@connections}"
             when 'D'
               'dualgraph'
             else
               if @graphtype == '' && @this_graphtype != ''
                 @this_graphtype
               else
                 @graphtype
               end
             end

split_in_out = case @graphtype
               when 'graphT', 'dualgraph'
                 true # actually doesn't matter, as it isn't looked at in this case.
               when 'singlegraph', 'graph3d', 'graphC', 'graphP', 'graphP2', 'graphP3', 'graphC2', 'graphC3'
                 false
               else
                 @graphtype = 'dualgraph'
                 true
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
rescue Exception => e # rubocop:disable Lint/RescueException
  backtrace = e.backtrace[0].split(':')
  message = "MSG: (#{File.basename(backtrace[-3])} #{backtrace[-2]}): #{e.message.to_s.gsub('\'', '\\\'')}"
end

if @graphtype == 'graphT'
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
  else # rubocop: disable Lint/DuplicateBranch
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
    if @graphtype == 'graphT'
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
  rescue Exception => e # rubocop:disable Lint/RescueException
    backtrace = e.backtrace[0].split(':')
    message << "MSG: (#{File.basename(backtrace[-3])} #{backtrace[-2]}): #{e.message.to_s.gsub('\'', '\\\'')}"
  end
  if @traffic.length > 0
    @hosts = @hold
  end
end

def error_response(script:)
  <<~HTML
    #{@cgi.head do
        <<~HTML
          #{@cgi.title { 'Ping Graph Error' }}
          #{script}
          <META HTTP-EQUIV="Pragma" CONTENT="no-cache"
          <META NAME="ROBOTS" CONTENT="NOINDEX, NOFOLLOW">

        HTML
      end
    }
    #{@cgi.body { '<b>Error:</b> No host specified<p>' }}
  HTML
end

def ping_form(on:, hidden:)
  if on
    <<~HTML
      #{if @hosts[0] != ''
          <<~HTML
            Site <input type="text" name="host" value="#{@hosts[0]}" id="host" size="10">&nbsp;
          HTML
        end
      }
      Start of Interval <input type="text" name="start" value="#{Time.at(start).to_sql}" id="start">
      Days <input type="text" name="days" value="#{@form_days}" id="days" size="5">
      Hours <input type="text" name="hours" value="#{@form_hours}" id="hours" size="4">
      <input type="submit" value="Submit" name="submit">&nbsp;&nbsp;
      &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
      <BUTTON type="submit" value="C" name="connections"> Hosts </BUTTON>
      <BUTTON type="submit" value="C3" name="connections"> Host Hist </BUTTON>
      <BUTTON type="submit" value="P" name="connections"> Ports </BUTTON>
      <BUTTON type="submit" value="P3" name="connections"> Port Hist </BUTTON>
      <BUTTON type="submit" value="T" name="connections"> Usage </BUTTON>
      <BUTTON type="submit" value="D" name="connections"> Dual </BUTTON>
      <p>
    HTML
  elsif hidden
    <<~HTML
      #{if @hosts[0] != ''
          <<~HTML
            <b>#{@hosts[0]}</b>&nbsp;&nbsp;
            <input type="hidden" name="host" value="#{@hosts[0]}" id="host" size="10">
          HTML
        end
      }
      <input type="hidden" name="start" value="#{Time.at(start).to_sql}">
    HTML
  else # Full form
    <<~HTML
      <div style="text-align: center; float:left;">
      <input type="submit" value="<<" name="prevDay">
      <input type="submit" value="Last Day" name="lastDay">
      <input type="submit" value=">>" name="nextDay">
      &nbsp;&nbsp;&nbsp;&nbsp;
      <input type="submit" value="<<" name="prevHour">
      <input type="submit" value="Last Hour" name="lastHour">
      <input type="submit" value=">>" name="nextHour">
      </div>
      #{@start_date_time == '' ? '' : "<input type=\"hidden\" name=\"start\" value=\"#{@start_date_time}\">\n"}
      #{if @form_hours == 1.0 && @form_days == 0.0
          <<~HTML
            #{@yesterday == '' ? '' : "<input type=\"hidden\" name=\"yesterday\" value=\"#{@yesterday}\">\n"}
          HTML
        else
          <<~HTML
            <input type="hidden" name="hours" value="#{@form_hours}" >
            <input type="hidden" name="days" value="#{@form_days}">
          HTML
        end
      }
    HTML
  end
end

@form_days = (@hours / 24).to_i
@form_hours = @hours - (@form_days * 24)
script = <<~HTML
  <script type="text/javascript">
    function correct_form_on(the_form)
    {
      the_form.form_on.value = "#{@form_on == true ? 'off' : (@authenticated ? 'on' : 'off')}";
      the_form.submit();
    }
  </script>
HTML

@traffic_list = ''
@traffic.each do |t|
  @traffic_list << <<~HTML
    <input type="hidden" name="traffic" value="#{t}" id="traffic">
  HTML
end

auth_image = @authenticated ? '/images/unlocked.gif' : '/images/locked.gif'

@cgi.header('type' => 'text/html')
@cgi.out do
  @cgi.html do
    if @hosts.nil? || @hosts.length == 0
      error_response(script: script)
    else
      # Create host list with images
      begin
        host_list = ''
        @hosts.each do |h|
          if @no_ping != 'true'
            ping_record = Ping_Log.new(@mysql_conf)
            if ping_record.gnuplot(h, Time.at(start), Time.at(end_time)).nil?
              images << <<~HTML
                <p><img src="/#{NETSTAT_DIR}/#{h}-p5f.png"></p>
              HTML
            end
          end
          host_list << <<~HTML
            <input type="hidden" name="host" value="#{h}" id="host">
          HTML
        end
      rescue Exception => e # rubocop:disable Lint/RescueException
        backtrace = e.backtrace[0].split(':')
        message << "MSG: (#{File.basename(backtrace[-3])} #{backtrace[-2]}): #{e.message.to_s.gsub('\'', '\\\'')}"
        host_list = ''
      end

      # Create signal list with images
      begin
        signal_list = ''
        @signal.each do |h|
          signal_record = Signal_Class.new(@mysql_conf)
          if (error = signal_record.gnuplot(h, Time.at(start), Time.at(end_time)) ).nil?
            images << <<~HTML
              <p><img src="/#{NETSTAT_DIR}/#{h}-signal.png"></p>
            HTML
          else
            message << error.to_s
          end
          signal_list << <<~HTML
            <input type="hidden" name="signal" value="#{h}" id="signal">
          HTML
        end
      rescue Exception => e # rubocop:disable Lint/RescueException
        backtrace = e.backtrace[0].split(':')
        message << "MSG: (#{File.basename(backtrace[-3])} #{backtrace[-2]}): #{e.message.to_s.gsub('\'', '\\\'')}"
        signal_list = ''
      end

      # HTML response
      <<~HTML
        #{@cgi.head do
            <<~HTML
              #{@cgi.title { "#{@hosts.join(',')} Pings" }}
              #{script}
              <META HTTP-EQUIV="Pragma" CONTENT="no-cache">
              <META NAME="ROBOTS" CONTENT="NOINDEX, NOFOLLOW">

            HTML
          end
        }

        #{@cgi.body do
            <<~HTML
              <!-- Graph failed with message: #{message}  -->
              <form name="traffic" id="traffic" method="get" >
              <div style="text-align: right; FONT-FAMILY:Arial ; font-size: 10px; margin-top:0; margin-left:0;">
              <input type="hidden" name="form_on" value="#{@form_on == true ? 'on' : 'off'}" id="form_on">
              <a href="/ruby/login.rbx?#{@authenticated ? 'action=logout&' : ''}ReturnURL='#{CGI.escapeHTML(ENV.fetch('SCRIPT_NAME', nil) + encode)}'"><img src="#{auth_image}"/></a>
              <input type="image" src="#{@form_on == true ? '/images/expandedTriangle.gif' : '/images/closedTriangle.gif'}"  onclick="correct_form_on(this.form)" />
              #{Time.now}</div><br>
              #{ <<~HTML if @dist
                <input type="hidden" name="dist" value="true" id="dist">
              HTML
              }
              #{<<~HTML if @link == 'true'
                <input type="hidden" name="link" value="true" id="link">
              HTML
              }
              #{<<~HTML if @no_ping == 'true'
                <input type="hidden" name="noping" value="#{@no_ping}" id="noping">
              HTML
              }
              #{<<~HTML if @graphtype == ''
                <input type="hidden" name="this_graphtype" value="#{@graphtype}">
              HTML
              }
              #{<<~HTML if @no_traffic == 'true'
                <input type="hidden" name="no_traffic" value="#{@no_traffic}">
              HTML
              }
              #{if @graphtype == 'graphT'
                  <<~HTML
                    <div style="text-align: left; ">
                      #{ping_form(on: form_on, hidden: true)}
                      <input type="submit" value="<<" name="prevMonth">
                      <input type="submit" value="This Month" name="thisMonth">
                      <input type="submit" value=">>" name="nextMonth">
                    </div>
                  HTML
                else
                  <<~HTML
                    #{@traffic_list}
                    #{host_list}
                    #{signal_list}
                    #{ping_form(on: form_on, hidden: false)}
                  HTML
                end
              }

              <div style="text-align: right; float:right;">
                #{case @graphtype
                  when 'graphT'
                    break
                  when 'graph3d'
                    <<~HTML
                      <BUTTON type="submit" value="dualgraph" name="graphtype"><img src="/images/dualgraph.gif"></BUTTON>
                      <BUTTON type="submit" value="singlegraph" name="graphtype"><img src="/images/singlegraph.gif"></BUTTON>
                    HTML
                  when 'singlegraph'
                    <<~HTML
                      <BUTTON type="submit" value="#{@dist ? 'false' : 'true'}" name="dist_b"><img src="#{@dist ? '/images/expandedTriangle.gif' : '/images/closedTriangle.gif'}"></BUTTON>
                      <BUTTON type="submit" value="graph3d" name="graphtype"><img src="/images/graph3d.gif"></BUTTON>
                      <BUTTON type="submit" value="dualgraph" name="graphtype"><img src="/images/dualgraph.gif"></BUTTON>
                    HTML
                  else # dual graph
                    <<~HTML
                      <BUTTON type="submit" value="#{@dist ? 'false' : 'true'}" name="dist_b"><img src="#{@dist ? '/images/expandedTriangle.gif' : '/images/closedTriangle.gif'}"></BUTTON>
                      #{<<~HTML if @link == 'true'
                        <input type="hidden" name="link" value="true" id="link">
                      HTML
                      }
                      <BUTTON type="submit" value="graph3d" name="graphtype"><img src="/images/graph3d.gif"></BUTTON>
                      <BUTTON type="submit" value="singlegraph" name="graphtype"><img src="/images/singlegraph.gif"></BUTTON>
                    HTML
                  end
                }
              </div><br>
              </p>
              </form>
              #{format_images(images)}
            HTML
          end
        }
      HTML
    end
  end
end
