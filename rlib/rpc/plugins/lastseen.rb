#  MIT License Wikarekare.org rob@wikarekare.org
require_relative "#{RLIB}/monitor/lastseen_sql.rb"

# Map DB lastseen log
class LastSeen < RPC
  def initialize(cgi:, authenticated: false)
    super(cgi: cgi, authenticated: authenticated)
    @select_acl = [ 'hostname' ]
    @result_acl = [ 'hostname', 'ping_time' ]
    @set_acl = if authenticated
                 [ 'hostname', 'ping_time' ]
               else
                 []
               end
  end

  rmethod :create do |select_on: nil, set: nil, result: nil, **args|  # rubocop:disable Lint/UnusedBlockArgument"
    # new customer record
  end

  rmethod :read do |select_on: nil, set: nil, result: nil, **args|  # rubocop:disable Lint/UnusedBlockArgument"
    # Pull data about customer
    where_string = to_where(select_on: select_on, acceptable_list: @select_acl)
    select_string = to_result(result: result, acceptable_list: @result_acl)
    order_by_string = to_order(order_by: order_by, acceptable_list: @result_acl)
    return sql_single_table_select(table: 'lastping', select: select_string, where: where_string, order_by: order_by_string)
  end

  rmethod :update do |select_on: nil, set: nil, result: nil, **args|  # rubocop:disable Lint/UnusedBlockArgument"
    # change user fields
    where_string = to_where(select_on: select_on, acceptable_list: @select_acl)
    set_string = to_set(set: set, acceptable_list: @set_acl)
    raise 'Must specify where clause in update lastping' if where_string == ''

    return sql_single_table_update(table: 'lastping', set: set_string, where: where_string)
  end

  rmethod :delete do |select_on: nil, set: nil, result: nil, **args|  # rubocop:disable Lint/UnusedBlockArgument"
    # We don't actually do this.
  end

  # need to change this to incorporate Lastseen into new LastSeen
  rmethod :global_state do |select_on: nil, set: nil, result: nil, **args|  # rubocop:disable Lint/UnusedBlockArgument"
    lastseen = Lastseen.new(@db_config)
    return lastseen.global_state
  end
end
