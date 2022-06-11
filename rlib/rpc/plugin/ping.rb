# /usr/local/sbin/fping -C 1 -q wikk006

class Pings < RPC
  def initialize(authenticated = false)
    super(authenticated)
    @select_acl = [ 'hostname' ]
    @set_acl = []
    @result_acl = [ 'hostname', 'ms' ]
  end

  rmethod :create do |select_on: nil, set: nil, result: nil, **args|
    # new record
  end

  rmethod :read do |select_on: nil, set: nil, result: nil, order_by: nil, **_args|
    select_on.each { |k, _v| acceptable(value: k, acceptable_list: @select_acl) } if select_on != nil
    result.each { |k, _v| acceptable(value: k, acceptable_list: @result_acl) } if result != nil
    ms = '-'
    `/usr/local/sbin/fping -C 1 -q #{hostname}`.each_line { |l| ms = l.split(' ')[2] }
    return { hostname: hostname, ms: ms }
  end

  rmethod :update do |select_on: nil, set: nil, result: nil, **args|
    # We don't actually do this.
  end

  rmethod :delete do |select_on: nil, set: nil, result: nil, **args|
    # We don't actually do this.
  end
end
