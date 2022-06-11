#!/usr/local/bin/ruby
require 'cgi'
require 'wikk_web_auth'
require 'wikk_configuration'

RLIB = '../../../rlib/'
require "#{RLIB}/wikk_conf.rb"
require "#{RLIB}/monitor/lastseen_sql.rb"
require "#{RLIB}/monitor/ping_log.rb"
require "#{RLIB}/monitor/signal_log_new.rb"
require "#{RLIB}/account/graph_sql_traffic.rb"

require 'cgi/session'
require 'cgi/session/pstore'     # provides CGI::Session::PStore

def decode
  @cgi = CGI.new('html4Tr')

  @hosts = @cgi.params['host']
  @start_date_time_str = CGI.escapeHTML(@cgi['start'])
  @hours_str = CGI.escapeHTML(@cgi['hours'])
  @days_str = CGI.escapeHTML(@cgi['days'])
  @lastseen = CGI.escapeHTML(@cgi['lastseen'])

  @graph_type = @cgi.params['graphtype']
end

def cal_time_range
  @hours = @hours_str == '' ? 0.0 : @hours_str.to_f
  @days = @days_str == '' ? 0.0 : @days_str.to_f
  @hours = 1.0 if @hours == 0 && @days == 0

  if @lastseen != nil && @lastseen != ''
    lastseen_record = Lastseen.new(@mysql_conf)
    if (d = lastseen_record.find(@hosts[0])).nil?
      @start_date_time = Time.now.to_i - (@hours * 3600).to_i # Not seen at all, so default to the last hour.
    else
      @start_date_time = d.to_i - 1800 # One half hour either side of the last seen time
      @hours = 1.0
      @days = 0.0
    end
  elsif @start_date_time_str != nil && @start_date_time_str != ''
    begin
      @start_date_time = Time.parse(@start_date_time_str).to_i
    rescue Exception => e # Ignore error and assume last hour
      @start_date_time = Time.now.to_i - (@days * 86400 + @hours * 3600).to_i
    end
  else # Default to last hour
    @start_date_time = Time.now.to_i - (@days * 86400 + @hours * 3600).to_i # Not specified, so default to the last period.
  end
  @end_time = @start_date_time + (@days * 86400 + @hours * 3600).to_i
end

def auth_needed?
  @graph_type.each do |gt|
    return true if [ 'usage', 'hosts', 'host_histogram', 'ports', 'port_histogram', 'signal' ].include?(gt)
  end
  return false
end

def process_host_list
  if @hosts != nil && @hosts.length > 0
    # not sure why, but 0 length array causes silent exception in @cgi, but not if run from cli ruby
    @hosts.collect! { |h| CGI.escapeHTML(h) } # .sub(/external/,'link')
  else
    @hosts = [ '' ] # saves a test later
  end
end

def process_graph_list
  if @graph_type != nil && @graph_type.length > 0
    # not sure why, but 0 length array causes silent exception in @cgi, but not if run from cli ruby
    @graph_type.collect! { |h| CGI.escapeHTML(h) }
    begin
      @authenticated = WIKK::Web_Auth.authenticated?(@cgi)
    rescue Exception => e
      @authenticated = false
    end

    if auth_needed? && !@authenticated
      @graph_type = [ 'traffic_split', 'ping' ] # Restrict what we will return
    end
  else
    @graph_type = [ 'traffic_split', 'ping' ] # saves a test later
  end
end

def gen_images
  @images = []
  @message = []

  @hosts.each do |h|
    @graph_type.each do |gt|
      begin
        case gt
        when 'usage'
          @images << if h == '' || h == 'all'
                       Graph_Total_Usage.new(@mysql_conf, nil, Time.at(@start_date_time), Time.at(@end_time)).images
                     else
                       Graph_Host_Usage.new(@mysql_conf, h, Time.at(@start_date_time), Time.at(@end_time)).images
                     end
        when 'graph3d'
          @images << if h == '' || h == 'all'
                       Graph_3D.new(@mysql_conf, 'all', true, Time.at(@start_date_time), Time.at(@end_time) ).images
                     else
                       Graph_3D.graph_parent(@mysql_conf, h, true, Time.at(@start_date_time), Time.at(@end_time) ).images
                     end
        when 'hosts'; # Bubble graph of connected hosts
          @images << if h =~ /wikk[0-9][0-9][0-9]/
                       Graph_Connections.new(h + '-net', Time.at(@start_date_time), Time.at(@end_time)).images
                     else
                       Graph_Connections.new(h, Time.at(@start_date_time), Time.at(@end_time)).images
                     end
        when 'host_histogram'; # Histogram of hosts
          @images << if h =~ /wikk[0-9][0-9][0-9]/
                       Graph_flow_Host_Hist_trim.new(h + '-net', Time.at(@start_date_time), Time.at(@end_time)).images
                     else
                       Graph_flow_Host_Hist_trim.new(h, Time.at(@start_date_time), Time.at(@end_time)).images
                     end
        when 'ports'; # Bubbles of
          @images << if h =~ /wikk[0-9][0-9][0-9]/
                       Graph_Ports.new(h + '-net', Time.at(@start_date_time), Time.at(@end_time)).images
                     else
                       Graph_Ports.new(h, Time.at(@start_date_time), Time.at(@end_time)).images
                     end
        when 'port_histogram'; # Port histogram
          @images << if h =~ /wikk[0-9][0-9][0-9]/
                       Graph_Flow_Ports_Hist_trim.new(h + '-net', Time.at(@start_date_time), Time.at(@end_time)).images
                     else
                       Graph_Flow_Ports_Hist_trim.new(h, Time.at(@start_date_time), Time.at(@end_time)).images
                     end
        when 'signal'
          signal_record = Signal_Class.new(@mysql_conf)
          if (error = signal_record.gnuplot(h, Time.at(@start_date_time), Time.at(@end_time)) ).nil?
            @images << "<p><img src=\"/netstat/#{h}-signal.png\"></p>\n"
          else
            @message << error.to_s
          end
        when 'traffic_split'
          @images << if h == 'all'
                       Graph_2D.graph_border(@mysql_conf, true, Time.at(@start_date_time), Time.at(@end_time) )
                     else
                       Graph_2D.new(@mysql_conf, h, true, Time.at(@start_date_time), Time.at(@end_time) ).images
                     end
        when 'traffic_dual'
          @images << if h == 'all'
                       Graph_2D.graph_border(@mysql_conf, false, Time.at(@start_date_time), Time.at(@end_time) )
                     else
                       Graph_2D.new(@mysql_conf, h, false, Time.at(@start_date_time), Time.at(@end_time) ).images
                     end
        when 'ping'
          ping_record = Ping_Log.new(@mysql_conf)
          if (error = ping_record.gnuplot(h, Time.at(@start_date_time), Time.at(@end_time)) ).nil?
            @images << "<p><img src=\"/netstat/#{h}-p5f.png?start_time=#{Time.at(@start_date_time).xmlschema}&end_time=#{Time.at(@end_time).xmlschema}\"></p>\n"
          else
            @message << error.to_s
          end
        when 'graphP2'
          @images += if h =~ /wikk[0-9][0-9][0-9]/
                       Graph_Ports_Hist.new(h + '-net', Time.at(@start_date_time), Time.at(@end_time)).images
                     else
                       Graph_Ports_Hist.new(h, Time.at(@start_date_time), Time.at(@end_time)).images
                     end
        when 'graphC2'
          @images << if h =~ /wikk[0-9][0-9][0-9]/
                       Graph_Host_Hist.new(h + '-net', Time.at(@start_date_time), Time.at(@end_time)).images
                     else
                       Graph_Host_Hist.new(h, Time.at(@start_date_time), Time.at(@end_time)).images
                     end
        when 'dist'
          if h == 'all'
            @images << Graph_2D.graph_all(@mysql_conf, true, Time.at(@start_date_time), Time.at(@end_time) )
          else
            @images << Graph_2D.new(@mysql_conf, h, true, Time.at(@start_date_time), Time.at(@end_time)).images
            @images << Graph_2D.graph_clients(@mysql_conf, h, true, Time.at(@start_date_time), Time.at(@end_time) )
          end
        when 'pdist'
          @images << Graph_2D.new(@mysql_conf, h, true, Time.at(@start_date_time), Time.at(@end_time)).images
          ping_record = Ping_Log.new(@mysql_conf)
          if (error = ping_record.gnuplot(h, Time.at(@start_date_time), Time.at(@end_time)) ).nil?
            @images << "<p><img src=\"/netstat/#{h}-p5f.png?start_time=#{Time.at(@start_date_time).xmlschema}&end_time=#{Time.at(@end_time).xmlschema}\"></p>\n"
          else
            @message << error.to_s
          end
          @images << Ping_Log.graph_clients(@mysql_conf, h, Time.at(@start_date_time), Time.at(@end_time) )
        when 'internal_hosts'
          @images << Graph_Internal_Hosts.new( h, Time.at(@start_date_time), Time.at(@end_time)).images
        else # Assume traffic split
          @images << if h == 'all'
                       Graph_2D.graph_border(@mysql_conf, true, Time.at(@start_date_time), Time.at(@end_time) )
                     else
                       Graph_2D.new(@mysql_conf, h, true, Time.at(@start_date_time), Time.at(@end_time) ).images
                     end
        end
      rescue Exception => e
        backtrace = e.backtrace[0].split(':')
        message = "MSG: (#{File.basename(backtrace[-3])} #{backtrace[-2]}): #{e.message.to_s.gsub(/'/, '\\\'')}\n"
        @message << message
      end
    end
  end
  @images.collect! { |im| im.gsub(/\n/, '') }
end

def quote_quotes(message)
  message.gsub(/"/, '\"')
end

@mysql_conf = WIKK::Configuration.new(MYSQL_CONF)

decode
cal_time_range
process_host_list
process_graph_list
gen_images

@hosts.collect! { |h| "\"#{h}\"" }
@graph_type.collect! { |gt| "\"#{gt}\"" }
@images.collect! { |im| "\"#{quote_quotes(im)}\"" }
@message.collect! { |m| "\"#{quote_quotes(m)}\"" }

@cgi.out('type' => 'application/json') do
  "{ \"start_date_time\": \"#{Time.at(@start_date_time).to_sql}\",\n" +
    "  \"end_time\": \"#{Time.at(@end_time)}\",\n" +
    "  \"days\": #{@days},\n" +
    "  \"hours\": #{@hours},\n" +
    "  \"hosts\": [ #{@hosts.join(',')} ],\n" +
    "  \"graph_type\": [ #{@graph_type.join(',')} ],\n" +
    "  \"images\": [ #{@images.join(',')} ],\n" +
    "  \"messages\": [ #{@message.join(',')} ],\n" +
    "  \"result_code\": #{@message.length}\n}"
end
