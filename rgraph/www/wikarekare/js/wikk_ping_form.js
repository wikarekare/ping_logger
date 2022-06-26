var wikk_ping_form = ( function() {
  //MIT License Wikarekare.org rob@wikarekare.org

  var simple_form = false;
  var hostname = null;
  var the_form = null;
  var now ;
  var tz;
  var this_month = false;
  var delay_sending = false;

  //Add monthDays to the Date class
  // @return [numeric] days in the month
  Date.prototype.monthDays= function() {
      var d = new Date(this.getFullYear(), this.getMonth()+1, 0);
      return d.getDate();
  }

  function set_days_hours() {
    var start_date = new Date(the_form.start_datetime.value.slice(0, 19).replace(' ', 'T')+'Z');
    var end_date = new Date(the_form.end_datetime.value.slice(0, 19).replace(' ', 'T')+'Z');
    if( start_date != null && end_date != null ) {
      dec_days = (end_date.getTime() - start_date.getTime())/86400000.0
      num_days = Math.floor(dec_days)
      the_form.days.value = num_days
      the_form.hours.value = (dec_days - num_days) * 864 / 36
    }
  }

  //Update date of the last request in the datetime span
  function set_now() {
    var datetime_span = document.getElementById('datetime');
    now = new Date();
    tz = (now.getTimezoneOffset()/60)*(-1);
    now.setHours(now.getHours() + tz);
    datetime_span.innerHTML = now.toISOString().slice(0, 19).replace('T', ' ');
  }

  function get_now() {
    return now;
  }

  function get_tz() {
    return (tz < 0 ? "" : "+") + (tz < 10 && tz > -10 ? "0" : "") + tz + ":00"
  }

  function date_offset(date, days, hours) {
    var new_date = new Date(date.value.slice(0, 19).replace(' ', 'T')+'Z');
    new_date.setSeconds(0);
    new_date.setDate(new_date.getDate() + days) ;
    new_date.setHours(new_date.getHours() + hours);
    return new_date.toISOString().slice(0, 19).replace('T', ' ');
  }

  function init(form_id, draw_div_id, the_hostname, start_time, end_time, days, hours) {
    hostname = the_hostname;
    the_form = document.getElementById(form_id);
    wikk_ping_graph.init(draw_div_id);
    init_start_datetime(start_time, end_time, days, hours)
  }

  function init_start_datetime(start_time, end_time, days, hours) {
    set_now();
    if(days == null) days = 0.0;
    if(hours == null) hours = (days == 0.0)  ? 1.0 : 0.0;
    if(hours == 0.0 && days == 0.0) hours = 1.0;
    the_form.days.value = days;
    the_form.hours.value = hours;

    if(start_time != null) {
      the_form.start_datetime.value = start_time
      if(end_time != null) {
        the_form.end_datetime.value = end_time
        start = new Date(start_time.slice(0, 19).replace(' ', 'T'));
        end = new Date(end_time.slice(0, 19).replace(' ', 'T'));
        dec_days = (end.getTime() - start.getTime())/86400000.0
        num_days = Math.floor(dec_days)
        the_form.days.value = num_days
        the_form.hours.value = (dec_days - num_days) * 864 / 36
      } else {
        the_form.end_datetime.value = date_offset(the_form.start_datetime, days, hours)
      }
    } else {
      if(end_time != null) {
        the_form.end_datetime.value = end_time
        the_form.start_datetime.value = date_offset(the_form.end_datetime, -days, -hours)
      } else {
        var end_date = now;
        end_date.setSeconds(0);
        the_form.end_datetime.value = end_date.toISOString().slice(0, 19).replace('T', ' ');
        the_form.start_datetime.value = date_offset(the_form.end_datetime, -days, -hours);
      }
    }
    this_month = false;
  }

  function post_form(button_id) {
    set_now();
    set_days_hours();
    ping_graph();
    distribution_graph();
  }

  function ping_graph() {
    wikk_ping_data.ping_data(the_form, wikk_ping_graph.graph_pings);
  }

  function distribution_graph() {
    set_now();
    wikk_ping_buckets.ping_buckets(the_form, wikk_ping_freq_graph.graph_ping_histogram);
  }

  function set_last_seen_callback(last_seen_record) {
    if(last_seen_record != null && last_seen_record.length == 1) {
      the_form.days.value = 0.0;
      the_form.hours.value = 1.0;
      the_form.end_datetime.value = last_seen_record[0].ping_time;
      the_form.start_datetime.value = date_offset(the_form.end_datetime, 0.0, -1.0)
    }
  }

  function set_last_seen() {
    wikk_last_seen.get_last_seen(set_last_seen_callback, 0);
  }

  function set_today() {
    set_now();
    var start_date = now;
    tz = (now.getTimezoneOffset()/60)*(-1);
    start_date.setHours(start_date.getHours() - tz);
    year = start_date.getFullYear();
    month = start_date.getMonth() + 1; //jan == 0?
    day = start_date.getDate();
    the_form.start_datetime.value = year + '-' + ("0" + month).slice(-2) + '-' + ("0" + day).slice(-2) + ' 00:00:00'
    the_form.days.value = 1.0;
    the_form.hours.value = 0.0;
    the_form.end_datetime.value = date_offset(the_form.start_datetime, 1.0, 0.0)
    this_month = false;
  }

  function set_last_hour() {
    init_start_datetime();
  }

  function set_last_period() {
    set_now();
    var end_date = now;
    end_date.setSeconds(0);
    the_form.end_datetime.value = end_date.toISOString().slice(0, 19).replace('T', ' ');
    days = -parseFloat(the_form.days.value)
    hours = -parseFloat(the_form.hours.value)
    the_form.start_datetime.value = date_offset(the_form.end_datetime, days, hours)
  }

  function set_month(offset) {
    this_month = true;
    set_now();
    if(offset == 0) {
      var start_date = now
      start_date.setHours(start_date.getHours() - tz);
    } else {
      var start_date = new Date(the_form.start_datetime.value.slice(0, 19).replace(' ', 'T'));
    }
    start_date.setMonth(start_date.getMonth() + offset);
    year = start_date.getFullYear();
    month = start_date.getMonth() + 1 ; //jan == 0?
    the_form.hours.value = 0.0
    the_form.days.value = start_date.monthDays();
    the_form.start_datetime.value = year + '-' + ("0" + month).slice(-2) + '-01 00:00:00'
    the_form.end_datetime.value = date_offset(the_form.start_datetime, parseFloat(the_form.days.value), 0.0)
  }

  function set_offset_period(direction) {
    if(this_month) {
      set_month(direction);
    } else {
      set_now();
      days = (direction * parseFloat(the_form.days.value))
      hours = (direction * parseFloat(the_form.hours.value))
      the_form.start_datetime.value = date_offset(the_form.start_datetime, days, hours)
      the_form.end_datetime.value = date_offset(the_form.start_datetime, parseFloat(the_form.days.value), parseFloat(the_form.hours.value))
    }
  }

  function set_week(direction) {
    if(direction == 0) {
      set_now();
      var start_date = now;
      start_date.setHours(start_date.getHours() - tz);
      year = start_date.getFullYear();
      month = start_date.getMonth() + 1; //jan == 0?
      day = start_date.getDate() - start_date.getDay() + 1;
      the_form.start_datetime.value = year + '-' + ("0" + month).slice(-2) + '-' + ("0" + day).slice(-2) + ' 00:00:00'
    }
    the_form.days.value = 7.0;
    the_form.hours.value = 0.0;
    this_month = false;
    set_offset_period(direction);
  }

  function set_offset_day(direction) {
    the_form.days.value = 1.0;
    the_form.hours.value = 0.0;
    this_month = false;
    set_offset_period(direction);
  }

  function set_offset_hour(direction) {
    the_form.days.value = 0.0;
    the_form.hours.value = 1.0;
    this_month = false;
    set_offset_period(direction);
  }

  function set_delayed(obj_ptr) {
    delay_sending = obj_ptr.checked;
  }

  //return a hash of key: function pairs, with the key being the same name as the function.
  //Hence call with wikk_ping.function_name()
  return {
    init: init,
    now: get_now,
    tz: get_tz,
    set_delayed: set_delayed,
    set_offset_hour: set_offset_hour,
    set_offset_day: set_offset_day,
    set_week: set_week,
    set_offset_period: set_offset_period,
    set_month: set_month,
    set_last_period: set_last_period,
    set_last_hour: set_last_hour,
    set_today: set_today,
    set_last_seen: set_last_seen,
    init_start_datetime: init_start_datetime,
    date_offset: date_offset,
    ping_graph: ping_graph,
    distribution_graph: distribution_graph,
    set_days_hours: set_days_hours,
    post_form: post_form
  };
})();
