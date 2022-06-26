var wikk_ping_data = ( function() {
  //MIT License Wikarekare.org rob@wikarekare.org

  var registered_local_completion = null;
  var result = null;

  function ping_data_error_callback(jqXHR, textStatus, errorMessage)
  {   var result_div = document.getElementById('result_div');
      last_result = null;
      result_div.innerHTML='Error:' + jqXHR.status.toString() + '<br>\n' + errorMessage;
  }

  function ping_data_completion(data) {   //Called when everything completed, including callback.
    if(registered_local_completion != null) {
      registered_local_completion(result);
    }
  }

  function ping_data_callback(data) { //should we have extra args ,status,xhr
    result = data.result;
  }

  function ping_data(the_form, local_completion=null) {
    registered_local_completion = local_completion;

    var args = {
      "method": "Pings.read",
      "kwparams": {
        "select_on": { "hostname":   the_form.host.value,
                       "start_time": the_form.start_datetime.value,
                       "end_time":   the_form.end_datetime.value,
                       "tz": wikk_ping_form.tz()
                      },
        "orderby": null,
        "set": null,
        "result": []
      },
      "version": 1.1
    }

    url = "/cgi/rpc.rbx"
    wikk_ajax.delayed_ajax_post_call(url, args, ping_data_callback, ping_data_error_callback, ping_data_completion, 'json', true, 0);

    return false;
  }

  //return a hash of key: function pairs, with the key being the same name as the function.
  //Hence call with wikk_ping.function_name()
  return {
    ping_data: ping_data
  };
})();
