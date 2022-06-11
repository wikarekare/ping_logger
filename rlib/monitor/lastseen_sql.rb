#!/usr/local/bin/ruby
require 'time'
require 'rubygems'
require 'mysql'
require_relative 'host_cluster.rb'

# Last time we recorded a successful ping for a host
class Lastseen
  # Multiple lines. Each a key\tdate time pair.

  JITTER = 30 # We expect small variations
  ORANGE_LIMIT = 60 + JITTER # Orange if not seen for a minute. The 30s allows for jitter.
  RED_LIMIT = 150 + ORANGE_LIMIT # seconds, i.e. 2.5 minutes beyond the ORANGE LIMIT.
  STATES =  { ok: 1, warning: 2, critical: 3, no_data_warning: 4, no_data_critical: 5, unknown: 6 }

  attr_reader :datetime, :clusters

  # Initialize the class, fetching the DB
  # @param db_conf [Hash] DB connection details
  # @param with_clusters [Boolean] fetch last pings, grouped by cluster. Defaults to true.
  def initialize(db_conf, with_clusters = true)
    @mysql_conf = db_conf
    sync
    @clusters = with_clusters ? Host_Cluster.new(db_conf).clusters : {}
  end

  def sync(_with_clusters = true)
    @hosts = {}
    @now = Time.now
    WIKK::SQL.connect(@mysql_conf) do |sql|
      # there will be one row with a dummy host name called 'datetime', which is the last time we recorded a ping time in the table.
      sql.each_row("select ping_time from lastping where hostname = 'datetime'") do |row|
        @datetime = Time.parse(row[0])
      end
      @datetime ||= @now # If there never has been a recorded ping, then default to the current time.

      # puts "Getting hosts and ping times from DB"
      # load the ping timestamps as at the time of the creation of the class.
      sql.each_row("select hostname, ping_time from lastping where hostname != 'datetime'  order by hostname") do |row|
        @hosts[row[0]] = row[1].nil? ? nil : Time.parse(row[1])
      end
    end
  end

  # find the time stamp of the last ping for the given host
  # @return [Time] the last time we successfully pinged this host
  def find(host)
    @hosts[host] # will return nil if the host doesn't exist in the hash.
  end

  # iterate through the time stamps of each host.
  # @yield [String,Time] hostname, and the time we last successfully pinged the host
  def each(&block)
    @hosts.each(&block)
  end

  # Return all records as a multiline string. for debugging purposes.
  # @return [String] hostname\tlastping_time\n...
  def to_s
    s = "datetime\t#{@datetime} (#{@now})\n"
    @hosts.each do |host, datetime|
      s += "#{host}\t#{datetime.nil? ? '0000-00-00 00:00:00' : datetime.strftime('%Y-%m-%d %H:%M:%S')}\t#{host_color(host)}\n"
    end
    return s
  end

  # Have we successfully recorded a ping for any host within the RED_LIMIT
  # @return [Boolean] True if last recorded ping for any host is more than ORANGE_LIMIT seconds plus normal jitter
  def red_datetime?
    @now > @datetime + RED_LIMIT
  end

  # Have we successfully recorded a ping for any host within the ORANGE_LIMIT
  # @return [Boolean] True if last recorded ping for any host is more than DATETIME_LIMIT seconds (normal jitter)
  def orange_datetime?
    @now > @datetime + ORANGE_LIMIT && !red_datetime?
  end

  # Have we pinged this host within the RED_LIMIT
  # @return [Boolean] true if ping beyond the RED_LIMIT
  def critical?(host)
    host_state(host) == :critical
  end

  # Have we pinged this host within the ORANGE_LIMIT
  # @return [Boolean] true if ping beyond the ORANGE LIMIT
  def warning?(host)
    host_state(host) == :warning
  end

  # Have we pinged this host within the JITTER period
  # @return [Boolean] true if ping below the ORANGE LIMIT
  def ok?(host)
    host_state(host) == :ok
  end

  # Can this hosts ping status be determined
  # @return [Boolean] true if we have no record for this host
  def unknown?(host)
    host_state(host) == :unknown
  end

  # Colours used to draw nodes in status graphs
  # @param state [Enum] ping state of the host
  # @return [String] colour to use in graph
  def state_colour(state)
    case state
    when :no_data_critical then 'purple'  # Ping logging has failed for all hosts Beyond the RED LIMIT
    when :no_data_warning then 'blue'     # Ping logging has failed for all hosts Beyond the ORANGE LIMIT
    when :critical then 'red'             # Beyond the RED_LIMIT for a host
    when :warning then 'orange'           # Beyond the ORANGE LIMIT for a host
    when :ok then 'green'                 # Within the JITTER LIMIT for a host
    when :unknown then 'black'            # Dont know the state of a host. No record in the DB. The host is new, or not in the fping hosts file.
    else 'black'                          # rubocop:disable Lint/DuplicateBranch catch all. Shouldn't be possible.
    end
  end

  # Colour to use to draw the state of the specified host
  # @param host [String] hostname
  # @return [String] colour for this hosts state
  def host_colour(host)
    state_colour host_state(host)
  end

  # Which state is worse
  # @param v1 [ENUM] first state
  # @param v2 [ENUM] second state
  # @return [ENUM] state with the greatest numerical value
  def worst_state(v1, v2)
    STATES[v1] >= STATES[v2] ? v1 : v2
  end

  # Which state is better
  # @param v1 [ENUM] first state
  # @param v2 [ENUM] second state
  # @return [ENUM] state with the lowest numerical value
  def best_state(v1, v2)
    STATES[v1] <= STATES[v2] ? v1 : v2
  end

  # Cluster colour, for graphing the state of a cluster of hosts.
  # @param hosts [Array] hostnames of hosts in a cluster
  # @return [String] colour representing the status of the cluster
  def cluster_colour(hosts)
    worst = :ok        # Start with great optimism
    best = :unknown    # We don't yet know the best state

    # update the worst and best states for this cluster of hosts
    hosts.each do |host|
      this_host_state = host_state(host)
      worst = worst_state(worst, this_host_state)
      best = best_state(best, this_host_state)
    end

    return state_colour(best) if best == worst # all good or all bad.

    return state_colour(:warning) # some are good, some aren't
  end

  # Find the state of every host and every cluster of hosts
  # @return [Hash] colours to use in graph, keyed by host and cluster names.
  def global_state
    state = {}

    # Get the state of every host.
    @hosts.each do |key, _date|
      state[key] = host_colour(key)
    end

    # Also get the state of named clusters of hosts.
    @clusters.each do |cluster, hosts|
      state[cluster] = cluster_colour(hosts)
    end

    return state
  end

  def self.test
    Lastseen.new.global_state.each do |key, value|
      print "#{key}\t#{value}\n"
    end
  end

  def self.record_pings(mysql_conf, hosts, datetime)
    WIKK::SQL.connect(mysql_conf) do |sql|
      sql.transaction do # doing this to ensure we have a consistent state in the Round Robin indexes.
        sql.query("insert into lastping (hostname, ping_time) values ('datetime', '#{datetime.strftime('%Y-%m-%d %H:%M:%S')}') ON DUPLICATE KEY UPDATE ping_time='#{datetime.strftime('%Y-%m-%d %H:%M:%S')}'")
        hosts.each do |host|
          sql.query("insert into lastping (hostname, ping_time) values ('#{host}', '#{datetime.strftime('%Y-%m-%d %H:%M:%S')}') ON DUPLICATE KEY UPDATE ping_time='#{datetime.strftime('%Y-%m-%d %H:%M:%S')}'")
        end
      end
    end
  end

  # Date arithmitic.
  # @param ping_time [Time] A hosts last ping time.
  # @return the number of seconds between the last recorded ping, and the ping_time
  private def seconds_diff(ping_time)
    (@datetime - ping_time).to_i
  end

  # determine a host's state
  # @param host [String] hosts name
  # @return [Symbol] index into the STATES hash, being used as an ENUM
  private def host_state(host)
    return :unknown if @hosts[host].nil? # we don't have a ping recorded.
    return :no_data_critical if red_datetime? # haven't recorded any pings in quit a while.
    return :no_data_warning if orange_datetime? # haven't recorded any pings in a short while.
    return :critical if seconds_diff(@hosts[host]) > RED_LIMIT
    return :ok if seconds_diff(@hosts[host]) == 0 # should be exact as we timestamp the pings in batches.
    return :warning if seconds_diff(@hosts[host]) <= RED_LIMIT

    return :unknown # shouldn't be able to get here.
  end
end

# Lastseen.test
# puts Lastseen.new.clusters
