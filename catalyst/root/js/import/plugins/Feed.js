Paperpile.PluginPanelFeed = Ext.extend(Paperpile.PluginPanel, {

  initComponent: function() {
    Ext.apply(this, {
      title:this.title,
      iconCls:'pp-icon-feed'
    });

    Paperpile.PluginPanelFeed.superclass.initComponent.call(this);
  },

  createGrid: function(gridParams) {
    return new Paperpile.PluginGridFeed(gridParams);
  }

});

Paperpile.PluginGridFeed = Ext.extend(Paperpile.PluginGridDB, {

    plugin_base_query:'',
    plugin_iconCls: 'pp-icon-feed',
    plugin_name:'Feed',
   
    plugins:[
      new Paperpile.ImportGridPlugin()
    ],

    initComponent:function() {
      this.createStore();
        this._store.setBaseParam('plugin_url',this.plugin_url);
        this._store.setBaseParam('plugin_id',this.plugin_id);

      Paperpile.PluginGridFeed.superclass.initComponent.call(this);


        this.store.on('beforeload',
                      function(){
                          Paperpile.status.showBusy('Parsing feed.');
                      }, this);
        
        this.store.on('load',
                      function(){
                          Paperpile.status.clearMsg();
                      }, this);

    },

    createToolbarMenu: function() {
      Paperpile.PluginGridFeed.superclass.createToolbarMenu.call(this);

      this.getToolbarByItemId(this.actions['NEW'].itemId).setVisible(false);
    },

    updateToolbarItem: function(item) {
      Paperpile.PluginGridFolder.superclass.updateToolbarItem.call(this,item);
    }

});