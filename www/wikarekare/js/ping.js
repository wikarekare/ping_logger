var simple_form = false;
var now ;
var this_month = false;
var delay_sending = false;
var graph_type_map = {
  "pings_and_traffic": ['traffic_split', 'ping'],
  "ping": ['ping'],
  "pings": ['ping'],
  "last_seen": ['ping'], //Find the last ping we have seen, and graph at that point.
  "traffic": ['traffic_split'], //In/Out Graphs side by side
  "traffic_split": ['traffic_split'],
  "dualgraph": ['traffic_dual'], //In/Out stacked histogram
  "singlegraph": ['traffic_dual'],
  "hosts": ['hosts'], //bubble graph
  "host_histogram": ['host_histogram'],
  "ports": ['ports'], //bubble graph
  "port_histogram": ['port_histogram'],
  "usage": ['usage'], //Line plot
  "internal_hosts": ['internal_hosts'], //histogram
  "dist": ["dist"], //tower + its sites
  "pdist": ["pdist"], //pings for tower + its sites
  "graph3d": [ 'graph3d' ] //Multiple site/tower graphs in one 3D view
};

//Add monthDays to the Date class
// @return [numeric] days in the month
Date.prototype.monthDays= function(){
    var d = new Date(this.getFullYear(), this.getMonth()+1, 0);
    return d.getDate();
}

//Update date of the last request in the datetime span
function set_now() {
  var datetime_span = document.getElementById('datetime');
  window.now = new Date();
  var tzo = (window.now.getTimezoneOffset()/60)*(-1);
  window.now.setHours(window.now.getHours() + tzo);
  datetime_span.innerHTML = window.now.toISOString().slice(0, 19).replace('T', ' ');
}

function date_offset(date, days, hours) {
  var tzo = -window.now.getTimezoneOffset()/60;
  var new_date = new Date(date.value.slice(0, 19).replace(' ', 'T')+'Z');
  new_date.setSeconds(0);
  new_date.setDate(new_date.getDate() + days) ;
  new_date.setHours(new_date.getHours() + hours);
  return new_date.toISOString().slice(0, 19).replace('T', ' ');
}

function init_start_datetime(start_time, end_time, days, hours) {
  var the_form = document.getElementById('expanded_form');
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
      var end_date = window.now;
      end_date.setSeconds(0);
      the_form.end_datetime.value = end_date.toISOString().slice(0, 19).replace('T', ' ');
      the_form.start_datetime.value = date_offset(the_form.end_datetime, -days, -hours);
    }
  }
  window.this_month = false;
}


function post_form(button_id) {
  set_now();
  window.graph_type = graph_type_map[button_id];
  window.this_month = false;
  get_ping_data(button_id == 'last_seen')
}

function set_last_seen_callback(last_seen_record) {
  var the_form = document.getElementById('expanded_form');
  if(last_seen_record != null && last_seen_record.length == 1) {
    the_form.days.value = 0.0;
    the_form.hours.value = 1.0;
    the_form.end_datetime.value = last_seen_record[0].ping_time;
    the_form.start_datetime.value = date_offset(the_form.end_datetime, 0.0, -1.0)
    window.graph_type = graph_type_map['pings'];
    get_ping_data(false, window.delay_sending);
  }
}

function set_last_seen() {
  wikk_last_seen.get_last_seen(set_last_seen_callback, 0);
}

function set_last_traffic_callback(last_traffic_record) {
  var the_form = document.getElementById('expanded_form');
  if(last_traffic_record != null && last_traffic_record.length == 1) {
    the_form.days.value = 0.0;
    the_form.hours.value = 1.0;
    the_form.end_datetime.value = last_traffic_record[0].log_timestamp;
    the_form.start_datetime.value = date_offset(the_form.end_datetime, 0.0, -1.0)
    window.graph_type = graph_type_map['pings_and_traffic'];
    get_ping_data(false, window.delay_sending);
  }
}

function set_last_traffic() {
  wikk_traffic.get_last_traffic(set_last_traffic_callback, 0);
}


function get_ping_data(last_seen_set, delay_sending, local_completion) {
  if(last_seen_set == null) last_seen_set = false;
  if(delay_sending == null) delay_sending = false;
  if(site_name != null && (simple_form || delay_sending == false)) {
    var result_div = document.getElementById('result_div');
    //insert image to show we are working. Gets over written when the result come back.
    if(result_div.firstChild) {
      result_div.insertBefore(working_img, result_div.firstChild);
    } else {
      result_div.appendChild(working_img);
    }

    wikk_ping.gen_graphs(last_seen_set, local_completion);
  }
}

function post_form_today() {
  var the_form = document.getElementById('expanded_form');
  set_now();
  var start_date = window.now;
  var tzo = (window.now.getTimezoneOffset()/60)*(-1);
  start_date.setHours(start_date.getHours() - tzo);
  year = start_date.getFullYear();
  month = start_date.getMonth() + 1; //jan == 0?
  day = start_date.getDate();
  the_form.start_datetime.value = year + '-' + ("0" + month).slice(-2) + '-' + ("0" + day).slice(-2) + ' 00:00:00'
  the_form.days.value = 1.0;
  the_form.hours.value = 0.0;
  the_form.end_datetime.value = date_offset(the_form.start_datetime, 1.0, 0.0)
  window.this_month = false;
  get_ping_data(false, window.delay_sending);
}

function post_form_last_hour() {
  init_start_datetime();
  get_ping_data(false, window.delay_sending);
}

function post_form_last_period() {
  var the_form = document.getElementById('expanded_form');
  set_now();
  var end_date = window.now;
  end_date.setSeconds(0);
  the_form.end_datetime.value = end_date.toISOString().slice(0, 19).replace('T', ' ');
  days = -parseFloat(the_form.days.value)
  hours = -parseFloat(the_form.hours.value)
  the_form.start_datetime.value = date_offset(the_form.end_datetime, days, hours)
  get_ping_data(false, window.delay_sending);
}

function post_form_month(offset) {
  window.this_month = true;
  var the_form = document.getElementById('expanded_form');
  set_now();
  if(offset == 0) {
    var start_date = window.now
    var tzo = (window.now.getTimezoneOffset()/60)*(-1);
    start_date.setHours(start_date.getHours() - tzo);
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
  get_ping_data(false, window.delay_sending);
}

function post_form_offset_period(direction) {
  if(window.this_month) {
    post_form_month(direction);
  } else {
    var the_form = document.getElementById('expanded_form');
    set_now();
    days = (direction * parseFloat(the_form.days.value))
    hours = (direction * parseFloat(the_form.hours.value))
    the_form.start_datetime.value = date_offset(the_form.start_datetime, days, hours)
    the_form.end_datetime.value = date_offset(the_form.start_datetime, parseFloat(the_form.days.value), parseFloat(the_form.hours.value))
    get_ping_data(false, window.delay_sending);
  }
}

function post_form_week(direction) {
  var the_form = document.getElementById('expanded_form');
  if(direction == 0) {
    set_now();
    var start_date = window.now;
    var tzo = (window.now.getTimezoneOffset()/60)*(-1);
    start_date.setHours(start_date.getHours() - tzo);
    year = start_date.getFullYear();
    month = start_date.getMonth() + 1; //jan == 0?
    day = start_date.getDate() - start_date.getDay() + 1;
    the_form.start_datetime.value = year + '-' + ("0" + month).slice(-2) + '-' + ("0" + day).slice(-2) + ' 00:00:00'
  }
  the_form.days.value = 7.0;
  the_form.hours.value = 0.0;
  window.this_month = false;
  post_form_offset_period(direction);
}

function post_form_offset_day(direction) {
  var the_form = document.getElementById('expanded_form');
  the_form.days.value = 1.0;
  the_form.hours.value = 0.0;
  window.this_month = false;
  post_form_offset_period(direction);
}

function post_form_offset_hour(direction) {
  var the_form = document.getElementById('expanded_form');
  the_form.days.value = 0.0;
  the_form.hours.value = 1.0;
  window.this_month = false;
  post_form_offset_period(direction);
}

function set_delayed(obj_ptr) {
  delay_sending = obj_ptr.checked;
}
