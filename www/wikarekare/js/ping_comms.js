var wikk_ping = ( function() {
  var last_result = null;
  var registered_local_completion = null;

  function ping_form_error_callback(jqXHR, textStatus, errorMessage)
  {   last_result = null;
      result_div.innerHTML='Error:' + jqXHR.status.toString() + '<br>\n' + errorMessage;
  }

  function ping_form_completion(data) {   //Called when everything completed, including callback.
    if(registered_local_completion != null) {
      registered_local_completion(last_seen_record);
    }
  }

  function ping_form_callback(data) { //should we have extra args ,status,xhr
    var the_form = document.getElementById('expanded_form');
    var result_div = document.getElementById('result_div');
    var content = '';
    if(data != null){
      if(data.result != null) {
        last_result = data.result
        the_form.start_datetime.value = data.result.start_time;
        the_form.end_datetime.value = data.result.end_time;
        the_form.hours.value = data.result.hours;
        the_form.days.value = data.result.days;

        for(var im in data.result.images) {
          content += (data.result.images[im] + '\n');
        }
        if(data.result.messages != null) {
          content += "<p>"
          for(var m in data.result.messages) {
            content += (data.result.messages[m] + '<br>\n');
          }
        }
        result_div.innerHTML=content
      } else if(data.error != null) {
        content = "<h3>Error</h3><ul>";
        content += (data.error.message + '<br>\n');
        content += '</ul>';
        result_div.innerHTML=content;
      }
    } else {
      result_div.innerHTML="Failed";
    }
  }

  function gen_graphs(last_seen, local_completion) {
    if(last_seen == null) last_seen = false;
    registered_local_completion = local_completion;

    if(Array.isArray(window.site_name))
      hosts = window.site_name;
    else
      hosts = [ window.site_name ];

    var the_form = document.getElementById('expanded_form');
    var args = {
      "method": "GnuGraph.graph",
      "kwparams": {
        "select_on": { "hosts": hosts,
                       "start_time": the_form.start_datetime.value,
                       "end_time": the_form.end_datetime.value,
                       "last_seen": last_seen
                      },
        "orderby": null,
        "set": null,
        "result": graph_type
      },
      "version": 1.1
    }

    url = "/ruby/rpc.rbx"
    wikk_ajax.delayed_ajax_post_call(url, args, ping_form_callback, ping_form_error_callback, ping_form_completion, 'json', true, 0);

    return false;
  }

  //return a hash of key: function pairs, with the key being the same name as the function.
  //Hence call with wikk_ping.function_name()
  return {
    gen_graphs: gen_graphs,
    last_result: last_result
  };
})();
