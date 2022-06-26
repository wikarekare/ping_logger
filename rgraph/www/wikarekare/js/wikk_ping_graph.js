var wikk_ping_graph = ( function() {
  //MIT License Wikarekare.org rob@wikarekare.org

  var ping_svg_obj = null;
  var draw_div_id = null;

  function average(a) {
    if ( a.length == 0 ) { return 0; }
    var total = 0;
    for(var i = 0; i < a.length; i++) {
        total += a[i];
    }
    return total / a.length;
  }

  function median(a) {
    if ( a.length == 0 ) { return 0; }
    a.sort((a, b) => a - b);
    return (a[(a.length - 1) >> 1] + a[a.length >> 1]) / 2.0
  }

  function prepare_graph_data(result) {
    var points = result.rows;
    var graph_data = {
      hostname: result.hostname,
      max_y: 1.0,
      xaxisTickmarks: [],
      xaxisTickmarksData: [],
      xaxisLabels: [],
      failed: [[],[],[],[],[]],
      no_data: [],
      stack_xaxisLabels: [],
      stack: [],
      midline: [],
      averageline: []
    };

    var line1 = [];
    var line2 = [];
    var line3 = [];
    var line4 = [];
    var line5 = [];
    var max_value = 0.0;

    //Find the overall maximum value, so we can set the yaxis max
    //Also check for failed pings, and calculate the median and average for each row
    for( var i = 0; i < points.length; i++ ) {
      //prefill nodata with 0s. Using separate index 't', as we may insert entries
      graph_data.no_data[i] = points[i].times.length == 0 ? 1:0 ;

      //prefill failure arrays with 0s, for this point.
      for(var j = 0; j < 5; j++ ) { graph_data.failed[j][i] = 0; }

      if (points[i].times[4] > max_value ) {
        max_value = points[i].times[4];
      }
      //remove -1 values, which represent a failed ping
      failed_index = -1; //no failed pings yet
      for(var j = 0; j < 5; j++) {
        if(points[i].times[0] == -1) {
          points[i].times.shift();  //remove the -1
          failed_index += 1;    //inc index
        }
      }
      points[i].failed_index = failed_index;
      points[i].median = median(points[i].times);
      points[i].average = average(points[i].times);
      if (points[i].median == 0) points[i].median = null ;
      if (points[i].average == 0) points[i].average = null;
    }
    //overall maximum y, for all points. Used to set yaxis range.
    graph_data.max_y = Math.trunc(max_value + 1);
    //if ( graph_data.max_y == 1 ) { graph_data.max_y = 5; }

    //refill ping rows, replicating the max row value in the missing columns
    //Also fix set the failed[] values for this point.
    for( var i = 0; i < points.length; i++ ) {
      //Set highest failure level's array value to max_y, so bar goes to the top.
      if (points[i].failed_index != -1) {
        graph_data.failed[points[i].failed_index][i] = graph_data.max_y;
      }

      if (points[i].times.length == 0 ) {
        //total failure, so all values infinite, but 0 is nicer.
        points[i].times = [0,0,0,0,0];
      }
      else {
        //Might be 1 or more failed points
        max_row_y = points[i].times[points[i].times.length-1];
        for(j=points[i].times.length; j < 5; j++ ) {
          points[i].times.push(max_row_y);
        }
      }

      graph_data.no_data[i] = graph_data.no_data[i] == 1 ? graph_data.max_y : 0;
    }

    //Converts the points array into individual plotting arrays
    p = 0;
    t = 0;
    for( var i = 0; i < points.length; i++ ) {
      if(i%(Math.trunc(points.length/4)) == 0) {
        graph_data.xaxisTickmarks.push(points[i].ping_time.replace(' ',"\n"));
        // want null values, as we don't want to draw labels
        graph_data.xaxisTickmarksData.push( null );
      }

      graph_data.stack_xaxisLabels[i] = '';
      graph_data.xaxisLabels[p] = '';
      graph_data.xaxisLabels[p+1] = '';
      graph_data.xaxisLabels[p+2] = '';

      //Stacked bars to render the ping variance from the mean.
      line1[i] = points[i].times[0];                   //transparent bar to this point
      line2[i] = points[i].times[1] - points[i].times[0];  //#eceeff
      line3[i] = points[i].times[2] - points[i].times[1];  //#ccccff
      line4[i] = points[i].times[3] - points[i].times[2];  //#ccccff
      line5[i] = points[i].times[4] - points[i].times[3];  //#eceeff
      graph_data.stack[i] = [line1[i],line2[i],line3[i],line4[i],line5[i]];

      //Median and Average lines, with a duplicate point either side, to create square wave
      graph_data.midline[p] = points[i].median;
      graph_data.averageline[p] = points[i].average;
      // duplicate points to the left
      graph_data.midline[p+1] = graph_data.midline[p];
      graph_data.averageline[p+1] = graph_data.averageline[p];
      // duplicate points to the right
      graph_data.midline[p+2] = graph_data.midline[p];
      graph_data.averageline[p+2] = graph_data.averageline[p];

      p += 3;
    }
    return graph_data;
  }

  function graph_pings(result) {
    //light to darker blue, then red, for 1 through 5 ping failures
    var failure_colours = ['#ccffff', '#99ffff', '#4dffff', '#00ffff', '#ff4455'];

    graph_data = prepare_graph_data(result);

    if (ping_svg_obj != null) {
      RGraph.SVG.clear(ping_svg_obj.svg);
    }

    ping_svg_obj = new RGraph.SVG.Line({
      id: draw_div_id,
      data: graph_data.xaxisTickmarksData,
      options: {
        title: "Ping times " + graph_data.hostname,
        key: ['Median','Average','No Data','1','2','3','4','All Failed'],
        keyColors: ['#000000','#00ff00', 'yellow', '#ccffff', '#99ffff', '#4dffff', '#00ffff', '#ff4455' ],

        yaxisScaleMin: 0,
        yaxisScaleMax: graph_data.max_y,
        yaxisScaleDecimals: 2,
        yaxisScaleRound: false,
        yaxisTitle: 'Ping Time in ms',

        marginTop: 55,
        marginRight: 35,
        marginLeft: 50,
        marginBottom: 70,
        backgroundGridVlines: false,
        backgroundGridBorder: false,

        linewidth: 1,
        textSize: 10,

        xaxis: true,
        xaxisLinewidth: 1,
        xaxisLabels: graph_data.xaxisTickmarks,
        xaxisTickmarksLength: 12
      }
    }).draw();

    //for the 5 failure colour, draw a bar for the ping_time.
    for(var j = 0; j < 5; j++) {
      new RGraph.SVG.Bar({
          id: draw_div_id,
          data: graph_data.failed[j],
          options: {
            yaxisScaleMin: 0,
            yaxisScaleMax: graph_data.max_y,
            yaxis: false,
            yaxisScale: false,
            yaxisTickmarks: false,

            xaxisTickmarksCount: 0,
            xaxisTickmarks: false,
            xaxis: false,
            xaxisLinewidth: 1,

            backgroundGridVlines: false,
            backgroundGridHlines: false,
            backgroundGridBorder: false,
            backgroundGrid: false,

            colors:[failure_colours[j]],
            textSize: 10,
            xaxisLabels: graph_data.stack_xaxisLabels,
            marginTop: 55,
            marginRight: 35,
            marginLeft: 50,
            marginBottom: 70,

            marginInner: 0,
          }
      }).draw();
    }

    //no data. yellow background, if no data for this point.
    new RGraph.SVG.Bar({
        id: draw_div_id,
        data: graph_data.no_data,
        options: {
          yaxisScaleMin: 0,
          yaxisScaleMax: graph_data.max_y,
          yaxis: false,
          yaxisScale: false,
          yaxisTickmarks: false,

          xaxisTickmarksCount: 0,
          xaxisLinewidth: 1,
          xaxisTickmarks: false,
          xaxis: false,
          xaxisLabels: graph_data.stack_xaxisLabels,

          backgroundGridVlines: false,
          backgroundGridHlines: false,
          backgroundGridBorder: false,
          backgroundGrid: false,

          colors:['#ffff88'],
          textSize: 10,
          marginTop: 55,
          marginRight: 35,
          marginLeft: 50,
          marginBottom: 70,
          marginInner: 0,
        }
    }).draw();

    new RGraph.SVG.Bar({
        id: draw_div_id,
        data: graph_data.stack,
        options: {
          yaxisScaleMin: 0,
          yaxisScaleMax: graph_data.max_y,
          yaxis: false,
          yaxisScale: false,
          yaxisTickmarks: false,

          xaxisTickmarksCount: 0,
          xaxisTickmarks: false,
          xaxisLinewidth: 1,
          xaxis: false,

          xaxisLabels: graph_data.stack_xaxisLabels,

          backgroundGridVlines: false,
          backgroundGridHlines: false,
          backgroundGridBorder: false,

          colors:['transparent', '#eceeff', '#ccccff', '#ccccff', '#eceeff'],
          grouping: 'stacked',
          textSize: 10,
          marginTop: 55,
          marginRight: 35,
          marginLeft: 50,
          marginBottom: 70,
          backgroundGrid: false,
          marginInner: 0,
        }
    }).draw();

    //Median and Average lines in Black and Green.
    new RGraph.SVG.Line({
        id: draw_div_id,
        data: [graph_data.midline, graph_data.averageline],
        options: {
          yaxisScaleMin: 0,
          yaxisScaleMax: graph_data.max_y,
          yaxis: false,
          yaxisScale: false,
          yaxisTickmarks: false,

          // Here's the colors being set - note the first is transparent
          // so we don't see it.
          colors: ['black','#00ff00'],
          marginTop: 55,
          marginRight: 35,
          marginLeft: 50,
          marginBottom: 70,
          backgroundGridVlines: false,
          backgroundGridHlines: false,
          backgroundGridBorder: false,
          linewidth: 1,

          xaxis: false,
          xaxisLinewidth: 1,
          xaxisLabels: graph_data.xaxisLabels,
          xaxisTickmarks: false,
        }
    }).draw();
  }

  function init(the_draw_div_id) {
    draw_div_id = the_draw_div_id;
  }

  return {
    init: init,
    graph_pings: graph_pings
  };
})();
