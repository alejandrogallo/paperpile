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

Paperpile.PubNotes = Ext.extend(Ext.Panel, {
  markup: [
    '<tpl if="annote">',
    '<div class="pp-action pp-action-edit-notes">',
    '<a href="#" class="pp-textlink" id="edit-notes-{id}">Edit Notes</a>',
    '</div>',
    '<div class="pp-notes">{annote}</div>',
    '</tpl>',
    '<tpl if="!annote">',
    '<div style="position:absolute; top:45%; left:45%;">',
    '<div class="pp-action pp-action-add-notes" id="add-notes-{id}">',
    '<a href="#" class="pp-textlink">Add notes</a>',
    '</div></div>',
    '</tpl>'],

  initComponent: function() {
    this.tpl = new Ext.XTemplate(this.markup);
    Ext.apply(this, {
      bodyStyle: {
        background: '#ffffff',
        padding: '7px'
      },
      autoScroll: true,
    });
    Paperpile.PubNotes.superclass.initComponent.call(this);

    this.spot = new Ext.ux.Spotlight({
      animate: false,
    });

  },

  updateDetail: function(data) {

    if (!this.grid) {
      this.grid = this.findParentByType(Paperpile.PluginPanel).items.get('center_panel').items.get('grid');
    }

    sm = this.grid.getSelectionModel();
    var numSelected = sm.getCount();
    if (this.grid.allSelected) {
      numSelected = this.grid.store.getTotalCount();
    }

    if (numSelected == 1) {
      this.data = sm.getSelected().data;

      var tpl = new Ext.XTemplate(this.markup);

      this.data.id = this.id;
      tpl.overwrite(this.body, this.data);

      this.installEvents();
    } else {
      var empty = new Ext.Template('');
      empty.overwrite(this.body);
    }

  },

  installEvents: function() {

    var addLink = Ext.get('add-notes-' + this.id);
    var editLink = Ext.get('edit-notes-' + this.id);

    if (addLink) {
      this.mon(addLink, 'click', this.editNotes, this);
    }
    if (editLink) {
      this.mon(editLink, 'click', this.editNotes, this);
    }

  },

  editNotes: function() {

    this.editor = new Ext.form.HtmlEditor({
      value: this.data.annote,
      itemId: 'html_editor',
    });

    var dataTabs = this.findParentByType(Paperpile.DataTabs);
    var bbar = dataTabs.getBottomToolbar();

    dataTabs.add(this.editor);

    bbar.items.get('summary_tab_button').hide();
    bbar.items.get('notes_tab_button').hide();
    bbar.items.get('collapse_button').hide();

    bbar.items.get('save_notes_button').show();
    bbar.items.get('cancel_notes_button').show();

    dataTabs.doLayout();
    dataTabs.getLayout().setActiveItem('html_editor');

    this.spot.show(this.ownerCt.id);

    this.mon(this.editor,'initialize', function(){this.editor.focus(20);},this,{single:true});
  },

  onSave: function() {

    var newNotes = this.editor.getValue();

    Paperpile.Ajax({
      url: '/ajax/crud/update_notes',
      params: {
        guid: this.data.guid,
        rowid: this.data._rowid,
        html: newNotes,
      },
      success: function(response) {
        this.closeEditor();
      },
      scope: this
    });

  },

  onCancel: function() {
    this.closeEditor();

  },

  closeEditor: function() {

    var dataTabs = this.findParentByType(Paperpile.DataTabs);
    var bbar = dataTabs.getBottomToolbar();

    dataTabs.remove('html_editor');
    bbar.items.get('summary_tab_button').show();
    bbar.items.get('notes_tab_button').show();
    bbar.items.get('collapse_button').show();
    bbar.items.get('save_notes_button').hide();
    bbar.items.get('cancel_notes_button').hide();

    dataTabs.doLayout();
    dataTabs.getLayout().setActiveItem('pubnotes');

    // id changes for some unknown reasons...
    this.data.id = dataTabs.items.get('pubnotes').id;

    this.tpl.overwrite(this.body, this.data);
    this.installEvents();

    this.spot.hide();

  },

  showEmpty: function(tpl) {
    var empty = new Ext.Template(tpl);
    empty.overwrite(this.body);
  }

});

Ext.reg('pubnotes', Paperpile.PubNotes);