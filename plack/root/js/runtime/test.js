Ext.onReady(function() {

  Ext.select('p#check').update('<i>Ext Core successfully loaded</i>');
  
  Ext.select('a#start-select-file-1').on('click',function(){testSelectFile(1)}, this);
  Ext.select('a#start-select-file-2').on('click',function(){testSelectFile(2)}, this);
  Ext.select('a#start-select-file-3').on('click',function(){testSelectFile(3)}, this);
  Ext.select('a#start-select-file-4').on('click',function(){testSelectFile(4)}, this);


  Ext.select('a#start-open-file').on('click',testOpenFile, this);
  Ext.select('a#start-open-url').on('click',testOpenUrl, this);
  Ext.select('a#start-open-folder').on('click',testOpenFolder, this);
  Ext.select('a#start-read-clipboard').on('click',testReadClipboard, this);
  Ext.select('a#start-write-clipboard').on('click',testWriteClipboard, this);
  Ext.select('a#start-ajax1').on('click',testAjax1, this);
  Ext.select('a#start-ajax2').on('click',testAjax2, this);
  Ext.select('a#start-plack').on('click',startPlack, this);
  Ext.select('a#restart-plack').on('click',restartPlack, this);
  Ext.select('a#kill-plack').on('click',killPlack, this);
  Ext.select('a#start-window-resize').on('click',resizeWindow, this);
  Ext.select('a#start-file-info').on('click',fileInfo, this);
  Ext.select('a#start-message-box').on('click',messageBox, this);
  Ext.select('a#start-log').on('click',log, this);

    window.QRuntime.plackExit.connect(
        function(error){
            Ext.select('pre#result-plack-status').update("Plack stopped.");
        }
    );


    window.QRuntime.plackReady.connect(
        function(){
            Ext.select('pre#result-plack-status').update("Plack started.");
        }
    );

    window.QRuntime.plackRead.connect(
        function(string) {
            Ext.select('pre#result-plack-output').update(string);
        }
    );


});


testSelectFile = function(type){

  var results;

  if (type == 1){

    
    results = window.QRuntime.fileDialog({'AcceptMode':'AcceptOpen', 
                                          'NameFilters':["BibTeX (*.bib)",
                                                         "Zotero, Mendeley (*.sqlite)",
                                                         "All supported files (*)"],
                                          'Caption': 'Test caption'
                                         });
  }

  if (type == 2){

    
    results = window.QRuntime.fileDialog({'AcceptMode':'AcceptSave', 
                                          'NameFilters':["BibTeX (*.bib)",
                                                         "Zotero (*.sqlite)",
                                                         "Paperpile (*.ppl)"],
                                          'RejectLabel':'Forget it'
                                         });
  }

  if (type == 3){

    
    results = window.QRuntime.fileDialog({'AcceptMode':'AcceptOpen', 
                                          'FileMode':'Directory',
                                         });
  }

  
  if (type == 4){

    
    results = window.QRuntime.fileDialog({'AcceptMode':'AcceptOpen', 
                                          'FileMode':'ExistingFiles',
                                         });
  }


  Ext.select('p#result-select-file-answer').update('<tt>'+results.answer+'</tt>').highlight();
  Ext.select('p#result-select-file-files').update('<tt>'+results.files.join(',')+'</tt>').highlight();
  Ext.select('p#result-select-file-filter').update('<tt>'+results.filter+'</tt>').highlight();
  
}

testOpenFile = function(){

  var file = window.QRuntime.getOpenFileName("Select any file","/","All files (*.*)");

  if (!file) return;

  window.QRuntime.openFile(file);
  
}

testOpenUrl = function(){

  window.QRuntime.openUrl("http://google.com");
  
}

testReadClipboard = function(){

  var text = window.QRuntime.getClipboard();
  
  Ext.select('p#result-read-clipboard').update('<tt>'+text+'</tt>').highlight();
  
}

testWriteClipboard = function(){

  window.QRuntime.setClipboard("Qt rocks!");

  Ext.select('p#result-write-clipboard').update('Clipboard updated!').highlight();
  
}



testAjax1 = function(){


  var xmlhttp=new XMLHttpRequest()
  try {
    xmlhttp.open('get', 'http://127.0.0.1:3210/ajax/app/heartbeat')
    xmlhttp.onreadystatechange = function(){
      if (xmlhttp.readyState == 4){
        alert("state 4" + xmlhttp.status+xmlhttp.responseText);
      }
      else {
        alert("state " + xmlhttp.readyState)
      }
    };
    xmlhttp.send(null);
  }
  catch (e){alert("An exception occurred in the script. Error name: " + e.name 
                  + ". Error message: " + e.message); 
           }

/*

  Ext.Ajax.request({
    url: 'http://127.0.0.1:3210/ajax/app/heartbeat',
    success: function(response, opts) {
      var obj = Ext.decode(response.responseText);
      alert('Success');
    },
    failure: function(response, opts) {
      alert('Failure'+response.status);
    }
  });

*/
}



testAjax2 = function(){


  /*
  var xmlhttp=new XMLHttpRequest()
  try {
    xmlhttp.open('get', 'http://127.0.0.1:3210/ajax/app/heartbeat')
    xmlhttp.onreadystatechange = function(){
      if (xmlhttp.readyState == 4){
        alert("state 4" + xmlhttp.status+xmlhttp.responseText);
      }
      else {
        alert("state " + xmlhttp.readyState)
      }
    };
    xmlhttp.send(null);
  }
  catch (e){alert("An exception occurred in the script. Error name: " + e.name 
                  + ". Error message: " + e.message); 
           }

*/

  debugger;

  Ext.Ajax.request({
    url: 'http://127.0.0.1:3210/ajax/app/heartbeat',
    success: function(response, opts) {
      var obj = Ext.decode(response.responseText);
      alert('Success');
    },
    failure: function(response, opts) {
      alert('Failure'+response.status);
    },
    xdomain:true
  });
}


startPlack = function(){

    window.QRuntime.plackStart();

}

killPlack = function(){
    window.QRuntime.plackKill();
}

restartPlack = function(){

    window.QRuntime.plackRestart();

}

resizeWindow = function(){
  window.QRuntime.resizeWindow(800,600);
}


fileInfo = function(){
  

  QRuntime.fileInfo("file:///Users/wash/test.txt");

}

messageBox = function(){
  
  //QRuntime.("file:///Users/wash/test.txt");

}

log = function(){
  
  QRuntime.log("This is a log message to STDERR");

}

testOpenFolder = function(){

  results = window.QRuntime.fileDialog({'AcceptMode':'AcceptOpen', 
                                        'FileMode':'Directory',
                                       });

  
  QRuntime.openFolder(results.files[0]);

}




