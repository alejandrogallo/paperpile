Paperpile.Dashboard = Ext.extend(Ext.Panel, {

    title: 'Dashboard',
    iconCls: 'pp-icon-dashboard',

    initComponent: function() {
		Ext.apply(this, {
            closable:true,
            autoLoad:{url: Paperpile.Url('/screens/dashboard'),
                      callback: this.setupFields,
                      scope:this
                     },
            
        });
		
        Paperpile.PatternSettings.superclass.initComponent.call(this);

    },

    setupFields: function(){



        var el = Ext.get('dashboard-last-imported');

        //console.log(Ext.get('dashboard-last-imported').dom.innerHTML);

        Ext.DomHelper.overwrite(el,Paperpile.utils.prettyDate(el.dom.innerHTML));

        this.body.on('click', function(e, el, o){

            switch(el.getAttribute('action')){
                
            case 'statistics':
                Paperpile.main.tabs.newScreenTab('Statistics');
                break;
            case 'settings-patterns':                 
                Paperpile.main.tabs.newScreenTab('PatternSettings');
                break;
            case 'settings-general':                 
                Paperpile.main.tabs.newScreenTab('GeneralSettings');
                break;
            }
        }, this, {delegate:'a'});

    },
});
