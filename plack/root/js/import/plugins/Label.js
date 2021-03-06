/* Copyright 2009-2011 Paperpile

   This file is part of Paperpile

   Paperpile is free software: you can redistribute it and/or modify it
   under the terms of the GNU Affero General Public License as
   published by the Free Software Foundation, either version 3 of the
   License, or (at your option) any later version.

   Paperpile is distributed in the hope that it will be useful, but
   WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Affero General Public License for more details.  You should have
   received a copy of the GNU Affero General Public License along with
   Paperpile.  If not, see http://www.gnu.org/licenses. */

Paperpile.PluginPanelLabel = Ext.extend(Paperpile.PluginPanel, {

  initComponent: function() {
    Ext.apply(this, {
      title: this.title,
      iconCls: 'pp-icon-empty'
    });

    Paperpile.PluginPanelLabel.superclass.initComponent.call(this);

    this.on('afterrender', this.myAfterRender, this);
  },

  myAfterRender: function() {
    this.getGrid().refreshCollections();
  },

  createGrid: function(gridParams) {
    return new Paperpile.PluginGridLabel(gridParams);
  },

  createAboutPanel: function() {
    return undefined;
  }

});

Paperpile.PluginGridLabel = Ext.extend(Paperpile.PluginGridDB, {

  plugin_iconCls: 'pp-icon-empty',
  plugin_name: 'DB',
  limit: 25,
  plugin_base_query: '',

  initComponent: function() {
    Paperpile.PluginGridLabel.superclass.initComponent.call(this);

    this.actions['REMOVE_FROM_LABEL'] = new Ext.Action({
      text: 'Remove label from references',
      cls: 'x-btn-text-icon',
      icon: '/images/icons/label_delete.png',
      handler: this.removeFromLabel,
      scope: this
    });

  },

  showBaseQueryInfo: function() {
    return false;
  },

  getGUID: function() {
    var match = this.plugin_base_query.match('labelid:(.*)$');
    var guid = match[1];
    return guid;
  },

  refreshCollections: function() {
    Paperpile.PluginGridLabel.superclass.refreshCollections.call(this);

    var pp = this.getPluginPanel();
    var guid = this.getGUID();

    // If we're a Label grid, update our title...
    var itemId = this.getPluginPanel().itemId;
    var labels = Ext.StoreMgr.lookup('label_store');
    var index = labels.findExact('guid', itemId);
    if (index !== -1) {
      var record = labels.getAt(index);
      var title = record.get('display_name');
      var style = record.get('style');
      var iconCls = 'pp-label-style-' + style;
      var tabDom = Paperpile.main.tabs.getTabEl(this.getPluginPanel());
      var tabEl = Ext.fly(tabDom);
      var textEl = tabEl.child('.x-tab-strip-text');
      for (var i = 0; i <= 24; i++) {
        textEl.removeClass('pp-label-style-' + i);
      }
      textEl.dom.innerHTML = title;
      textEl.addClass('pp-label-style-tab');
      textEl.addClass(iconCls);
    }

  },

  getEmptyBeforeSearchTemplate: function() {
    return new Ext.XTemplate(['<div class="pp-hint-box"><p>No references are tagged with this label. <a href="#" class="pp-textlink" action="close-tab">Close tab</a>.</p></div>']).compile();
  },

  initContextMenuItemIds: function() {
    Paperpile.PluginGridLabel.superclass.initContextMenuItemIds.call(this);
    var ids = this.contextMenuItemIds;

    //var index = ids.indexOf('DELETE');
    //ids.insert(index + 1, 'REMOVE_FROM_LABEL');
  },

  initToolbarMenuItemIds: function() {
    Paperpile.PluginGridLabel.superclass.initToolbarMenuItemIds.call(this);
    var ids = this.toolbarMenuItemIds;

    //var index = ids.indexOf('TB_FILL');
    //ids.insert(index + 1, 'REMOVE_FROM_LABEL');
  },

  updateButtons: function() {
    Paperpile.PluginGridLabel.superclass.updateButtons.call(this);

    var selection = this.getSingleSelectionRecord();
    if (!selection) {
      this.actions['REMOVE_FROM_LABEL'].disable();
    }
  },

  removeFromLabel: function() {
    var sel = this.getSelection();
    var grid = this;
    var match = this.plugin_base_query.match('labelid:(.*)$');
    var guid = match[1];

    var firstRecord = this.getSelectionModel().getLowestSelected();
    var firstIndex = this.getStore().indexOf(firstRecord);
    this.doAfterNextReload.push(function() {
      this.getSelectionModel().selectRow(firstIndex);
    });
    Paperpile.main.removeFromLabel(sel, grid, guid);
  },

  onUpdate: function(data) {
    Paperpile.PluginGridLabel.superclass.onUpdate.call(this, data);

    var pubs = data.pubs;
    if (!pubs) {
      return;
    }

    var refreshMe = false;
    for (var guid in pubs) {
      var update = pubs[guid];
      if (update['labels'] !== undefined) {
        refreshMe = true;
      }
    }
    if (refreshMe) {
      this.getView().holdPosition = true;
      this.getStore().reload();
    }
  }
});