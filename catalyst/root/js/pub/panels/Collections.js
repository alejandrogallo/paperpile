Ext.define('Paperpile.pub.panel.Collections', {
  extend: 'Paperpile.pub.PubPanel',
  alias: 'widget.Collections',
  initComponent: function() {
    Ext.apply(this, {});

    this.callParent(arguments);
  },

  viewRequiresUpdate: function() {
    var needsUpdate = false;
    Ext.each(this.selection, function(pub) {
      if (pub.modified.labels || pub.modified.folders) {
        needsUpdate = true;
      }
    });
    return needsUpdate;

  },

  createTemplates: function() {
    this.callParent(arguments);

    this.singleTpl = new Ext.XTemplate(
      '<div class="pp-box pp-box-side-panel pp-box-top pp-box-style1">',
      '<h2>Folders and Labels</h2>',
      '<tpl if="folders">',
      '  <dt>Folders: </dt>',
      '  <dd>',
      '    <ul class="pp-folders">',
      '    <tpl for="this.getFoldersList(folders)">',
      '      <li class="pp-folder-list pp-folder-generic">',
      '        <a href="#" class="pp-action pp-textlink" action="OPEN_FOLDER" args="{guid}">{name}</a> &nbsp;&nbsp;',
      '        <a href="#" class="pp-action pp-textlink pp-second-link" action="REMOVE_FOLDER" args="{guid}">Remove</a>',
      '      </li>',
      '    </tpl>',
      '    </ul>',
      '  </dd>',
      '</tpl>',
      '<tpl if="labels">',
      '  <dt>Labels: </dt>',
      '  <dd>',
      '    <div class="pp-labels-div">',
      '      <tpl for="this.getLabelsList(labels)">',
      '        <div class="pp-label-box pp-label-style-{style}">',
      '          <div class="pp-label-name pp-label-style-{style}">{name}</div>',
      '          <div class="pp-action pp-label-remove pp-label-style-{style}" action="REMOVE_LABEL" args="{guid}">x</div>',
      '        </div>',
      '      </tpl>',
      '    </div>',
      '  </dd>',
      '</tpl>',
      '<div style="clear:left;"></div>',
      '</div>', {
        getFoldersList: function(folders) {
          var guids = folders.split(',');
          var store = Ext.getStore('folders');
          var data = [];
          Ext.each(guids, function(guid) {
            if (guid) {
              var record = store.getById(guid);
              if (record) {
                data.push(record.data);
              } else {
                Paperpile.log("No record found for folder GUID " + guid);
              }
            }
          });
          return data;
        },
        getLabelsList: function(labels) {
          var guids = labels.split(',');
          var store = Ext.getStore('labels');
          var data = [];
          Ext.each(guids, function(guid) {
            if (guid) {
              var record = store.getById(guid);
              if (record) {
                data.push(record.data);
              } else {
                Paperpile.log("No record found for label GUID " + guid);
              }
            }
          });
          return data;
        }
      });
  }
});