# /usr/local/sbin/fping -C 1 -q wikk006
require 'time'

class Pings < RPC
  def initialize(authenticated = false)
    super(authenticated)
    @select_acl = [ 'hostname', 'start_time', 'end_time' ]
    @set_acl = []
    @result_acl = [ 'hostname', 'rows', 'affected_rows' ] # ignored for now.
  end

  def time_range(start_time:, end_time:, step: 60)
    while start_time < end_time
      yield(start_time)
      start_time += step
    end
  end

  rmethod :create do |select_on: nil, set: nil, result: nil, **args|  # rubocop:disable Lint/UnusedBlockArgument"
    # new record
  end

  rmethod :read do |select_on: nil, set: nil, result: nil, order_by: nil, **_args|  # rubocop:disable Lint/UnusedBlockArgument"
    query = <<-EOT
      SELECT ping_time, time1, time2, time3, time4, time5 FROM pinglog
      WHERE ping_time >= '#{select_on['start_time']}' and ping_time < '#{select_on['end_time']}' and host_name = '#{select_on['hostname']}'
      ORDER BY ping_time
    EOT
    last_time = Time.parse(select_on['start_time'])
    rows = []
    WIKK::SQL.connect(@config) do |sql|
      sql.each_hash(query) do |row|
        ping_time = Time.parse(row['ping_time'])
        time_range(start_time: last_time, end_time: ping_time, step: 60) do |t|
          rows << { 'ping_time' => t.strftime('%Y-%m-%d %H:%M:00'), 'times' => [] }
        end
        rows << { 'ping_time' => row['ping_time'], 'times' => [ row['time1'].to_f, row['time2'].to_f, row['time3'].to_f, row['time4'].to_f, row['time5'].to_f ] }
        last_time = ping_time + 60
      end

      time_range(start_time: last_time, end_time: Time.parse(select_on['end_time']), step: 60) do |t|
        rows << { 'ping_time' => t.strftime('%Y-%m-%d %H:%M:00'), 'times' => [] }
      end

      return { 'rows' => rows, 'affected_rows' => sql.affected_rows, 'hostname' => select_on['hostname'] }
    end
    return { 'rows' => [], 'affected_rows' => 0, 'hostname' => select_on['hostname'] }
  end

  rmethod :update do |select_on: nil, set: nil, result: nil, **args|  # rubocop:disable Lint/UnusedBlockArgument"
    # We don't actually do this.
  end

  rmethod :delete do |select_on: nil, set: nil, result: nil, **args|  # rubocop:disable Lint/UnusedBlockArgument"
    # We don't actually do this.
  end
end
