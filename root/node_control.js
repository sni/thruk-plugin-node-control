// used for updating all (visible) servers
function nc_run_all(mainBtn, cls, extraData) {
    setBtnSpinner(mainBtn, true);

    var list = [];
    jQuery(cls).each(function(i, el) {
        if(jQuery(el).is(":visible") && !jQuery(el).hasClass("invisible")) {
            list.push(el);
        }
    });

    var running = 0;
    var startNext = function() {
        if(list.length == 0) {
            if(running == 0) {
                setBtnNoSpinner(mainBtn);
            }
            return;
        }
        running++;
        var btn = list.shift();
        setBtnSpinner(btn, true);
        var form = jQuery(btn).parents('FORM');
        submitFormInBackground(form, function() {
            running--;
            setBtnNoSpinner(btn);
            startNext();

            // update table row
            var tr = jQuery(btn).parents('TR')[0];
            jQuery.get('node_control.cgi', {}, function(data, textStatus, jqXHR) {
                var table = jQuery(btn).parents('TABLE')[0];
                var newRow = jQuery(data).find('#'+tr.id);
                jQuery('#'+tr.id).replaceWith(newRow);
                applyRowStripes(table);
            });
        }, extraData);
    }
    var parallel = jQuery("INPUT[name='parallel']").val();
    for(var x = 0; x < parallel; x++) {
        startNext();
    }
}

function refresh_node_row(peer_id) {
    // update table row
    var tr = document.getElementById("node_row_"+peer_id);
    jQuery.get('node_control.cgi', {}, function(data, textStatus, jqXHR) {
        var table = jQuery(tr).parents('TABLE')[0];
        var newRow = jQuery(data).find('#'+tr.id);
        jQuery('#'+tr.id).replaceWith(newRow);
        applyRowStripes(table);
    });
}


// used to update service status
function nc_omd_service(btn, extraData) {
    setBtnSpinner(btn, true);

    var form = jQuery(btn).parents('FORM');
    submitFormInBackground(form, function() {
        setBtnNoSpinner(btn);

        // update table row
        var tr = jQuery(btn).parents('TR')[0];
        jQuery.get('node_control.cgi?action=omd_status&modal=1&peer='+extraData.peer, {}, function(data, textStatus, jqXHR) {
            var table = jQuery(btn).parents('TABLE')[0];
            var newRow = jQuery(data).find('#'+tr.id);
            jQuery('#'+tr.id).replaceWith(newRow);
            refresh_node_row(extraData.peer);
        });
    }, extraData);
}
