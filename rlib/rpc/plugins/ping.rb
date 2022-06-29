#  MIT License Wikarekare.org rob@wikarekare.org

# Data derived from /usr/local/sbin/fping  -C 5 -q -f hostfile, run every 60s
require 'time'

# Map db pinglog table
class Pings < RPC
  def initialize(authenticated = false)
    super(authenticated)
    @select_acl = [ 'hostname', 'start_time', 'end_time', 'tz' ]
    @set_acl = []
    @result_acl = [ 'hostname', 'rows', 'affected_rows', 'tz' ] # ignored for now.
  end

  rmethod :create do |select_on: nil, set: nil, result: nil, **args|  # rubocop:disable Lint/UnusedBlockArgument"
    # new record
  end

  rmethod :read do |select_on: nil, set: nil, result: nil, order_by: nil, **_args|  # rubocop:disable Lint/UnusedBlockArgument"
    last_time = Time.parse(select_on['start_time'])
    end_time = Time.parse(select_on['end_time'])
    time_diff = end_time - last_time

    # Sample less often, as the time period increases.
    if time_diff <= 86400 # 1 day, in seconds
      step_size = 60 # 1 minute intervals. for a day gives 1440 points.
      time_format_str = '%Y-%m-%d %H:%i:00'  # recover in 1m intervals of the logs
    else
      step_size = 3600 # 1 hour intervals, for 31 days gives 744 points
      time_format_str = '%Y-%m-%d %H:00:00'  # recover in 1 hour intervals of the logs
    end

    tz = select_on['tz'].nil? ? '00:00' : select_on['tz'].strip
    tz = "+#{tz}" if tz =~ /^[0-9].*/
    query = <<-SQL
      SELECT date_format(CONVERT_TZ(ping_time, "+00:00", '#{tz}'), "#{time_format_str}") as event_time,
             MIN(time1) as t1,
             if(MIN(time2) = -1, -1, MIN(time2)) as t2,
             if(MIN(time3) = -1, -1, AVG(time3)) as t3,
             if(MIN(time4) = -1, -1, MAX(time4)) as t4,
             if(MIN(time5) = -1, -1, MAX(time5)) as t5
      FROM pinglog
      WHERE ping_time >= CONVERT_TZ('#{select_on['start_time']}', '#{tz}', '+00:00')
      AND ping_time < CONVERT_TZ('#{select_on['end_time']}', '#{tz}', '+00:00')
      AND host_name like '#{select_on['hostname']}'
      GROUP BY event_time
      ORDER BY event_time
    SQL
    rows = []
    WIKK::SQL.connect(@db_config) do |sql|
      sql.each_hash(query) do |row|
        ping_time = row['event_time'].is_a?( String ) ? Time.parse(row['event_time']) : row['event_time']
        # Insert empty array, when time slot has no data. Will result in Yellow on graph.
        time_range(start_time: last_time, end_time: ping_time, step: step_size) do |t|
          rows << { 'ping_time' => t.strftime('%Y-%m-%d %H:%M:00'), 'times' => [] }
        end
        # Insert returned row
        rows << { 'ping_time' => row['event_time'], 'times' => [ row['t1'].to_f, row['t2'].to_f, row['t3'].to_f, row['t4'].to_f, row['t5'].to_f ] }
        last_time = ping_time + step_size
      end

      # Insert null rows to pad out to end time.
      time_range(start_time: last_time, end_time: Time.parse(select_on['end_time']), step: step_size) do |t|
        rows << { 'ping_time' => t.strftime('%Y-%m-%d %H:%M:00'), 'times' => [] }
      end

      return { 'rows' => rows, 'affected_rows' => sql.affected_rows, 'hostname' => select_on['hostname'], 'tz' => tz }
    end
    # Failed
    return { 'rows' => [], 'affected_rows' => 0, 'hostname' => select_on['hostname'], 'tz' => tz }
  end

  rmethod :update do |select_on: nil, set: nil, result: nil, **args|  # rubocop:disable Lint/UnusedBlockArgument"
    # We don't actually do this.
  end

  rmethod :delete do |select_on: nil, set: nil, result: nil, **args|  # rubocop:disable Lint/UnusedBlockArgument"
    # We don't actually do this.
  end

  # Fetch ping logs for the host, between the given start and end times.
  # Selecting on hostname with like, between start_time and end_time
  # Returning frequency in nbuckets.
  rmethod :buckets do |select_on: nil, set: nil, result: nil, order_by: nil, **_args| # rubocop:disable Lint/UnusedBlockArgument"
    nbuckets = select_on['nbuckets'].to_i
    last_time = Time.parse(select_on['start_time'])
    end_time = Time.parse(select_on['end_time'])

    # Need to check why a tz string with leading '+' has this replaced with a space
    tz = select_on['tz'].strip
    tz = "+#{tz}" if tz =~ /^[0-9].*/

    query = <<~SQL
      SELECT time1,time2,time3,time4,time5
      FROM pinglog
      WHERE ping_time >= CONVERT_TZ('#{select_on['start_time']}', '#{tz}', '+00:00')
      AND ping_time < CONVERT_TZ('#{select_on['end_time']}', '#{tz}', '+00:00')
      AND host_name like '#{select_on['hostname']}'
    SQL
    rows = []
    min = nil
    max = nil
    count = sum = sum2 = 0
    WIKK::SQL.connect(@config) do |sql|
      sql.each_hash(query) do |row|
        (1..5).each do |t|
          v = row["time#{t}"].to_f
          if v == -1
            rows << nil
          else # -1 is a failed ping
            max = v if max.nil? || v > max
            min = v if min.nil? || v < min
            sum += v
            sum2 += (v * v)
            count += 1
            rows << v
          end
        end
      end
      mean = sum / count.to_f
      variance = (sum2 - sum * sum / count) / (count - 1)
      stddev = Math.sqrt(variance)

      # Limit the graph to 4 standard deviations, but bound that with max and min values.
      graph_min = mean - 4 * stddev
      graph_max = mean + 4 * stddev
      buckets, bucket_labels = width_buckets(data: rows, min: graph_min > min ? graph_min : min, max: graph_max < max ? graph_max : max, nbuckets: nbuckets)
      return { 'buckets' => buckets,
               'bucket_labels' => bucket_labels, # Midpoint value for the bucket range
               'nbuckets' => nbuckets,
               'max_count' => buckets.max,
               'affected_rows' => sql.affected_rows,
               'hostname' => select_on['hostname'],
               'tz' => tz,
               'min' => min,
               'max' => max,
               'mean' => mean.round(3),
               'variance' => variance.round(3),
               'stddev' => stddev.round(3)
              }
    end
    # Failed.
    return { 'buckets' => [], 'bucket_labels' => [], 'nbuckets' => 0, 'max_count' => 0, 'affected_rows' => 0, 'hostname' => select_on['hostname'], 'tz' => tz }
  end

  # Create nbuckets, holding the frequency of values in data
  # Nb. nil in the data is ignored.
  # @param data [Array] Numeric values
  # @param min [Numeric] Minimum of range (values below this go into the first bucket)
  # @param max [Numeric] Maximum of range (values above this go into last bucket)
  # @param nbuckets [Integer] Number of buckets to divide the range into.
  # @return [Array,Array] The buckets, with the frequencies of the data values. And the mid points of each bucket.
  private def width_buckets(data:, min: nil, max: nil, nbuckets: 20)
    min ||= data.min                                # if we don't have a minimum, use the data array's minimum value
    max ||= data.max                                # if we don't have a maximum, use the data array's maximum value
    bucket_size = (max.to_f - min.to_f) / nbuckets  # Width of 1 bucket
    mid_value_base = min + bucket_size / 2.0        # half width of bucket above min, so first buckets middle value.

    # initialize buckets middle of range values, for graphing
    mid_values = []
    (0...nbuckets).each { |i| mid_values[i] = '%.3f' % (mid_value_base + bucket_size * i) }
    mid_values << 'lost'

    # Initialize bucket counts values to 0
    bucket = Array.new(nbuckets + 1, 0)

    # Increment bucket counts, based on the data values.
    data.each do |v|
      if v.nil?
        bucket[-1] += 1 # Had a lost ping
      else
        bucket_index = if v < min
                         0 # First bucket
                       elsif v >= max
                         nbuckets - 1 # last bucket
                       else
                         ((v - min) / bucket_size).truncate
                       end
        bucket[bucket_index] += 1
      end
    end
    return bucket, mid_values
  end

  # Enumerate from start to end time in step units.
  # Time can do this, but very inefficiently.
  # @param start_time [Time]
  # @param end_time [Time]
  # @param step [Integer] Seconds
  # @yield [Time]
  private def time_range(start_time:, end_time:, step: 60)
    while start_time < end_time
      yield(start_time)
      start_time += step
    end
  end
end
