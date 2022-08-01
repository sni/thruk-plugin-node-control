var ms_row_refresh_interval = 3000;
var ms_refresh_timer;
// add background refresh for all rows currently spinning
jQuery(document).ready(function() {
    window.clearTimeout(ms_refresh_timer);
    ms_refresh_timer = window.setTimeout(function() {
        refresh_all_changed_rows();
    }, ms_row_refresh_interval)
});

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

            refresh_all_changed_rows_now();
        }, extraData);
    }
    var parallel = jQuery("INPUT[name='parallel']").val();
    for(var x = 0; x < parallel; x++) {
        startNext();
    }
}

function refresh_all_changed_rows_now() {
    window.clearTimeout(ms_refresh_timer);
    ms_refresh_timer = window.setTimeout(function() {
        refresh_all_changed_rows();
    }, 200)
}

function refresh_all_changed_rows() {
    window.clearTimeout(ms_refresh_timer);
    ms_refresh_timer = null;
    var rows = jQuery("DIV.spinner").parents("TR");
    if(rows.length == 0) {
        ms_refresh_timer = window.setTimeout(function() {
            refresh_all_changed_rows();
        }, ms_row_refresh_interval)
        return;
    }
    jQuery.get('node_control.cgi', {}, function(data, textStatus, jqXHR) {
        var table = jQuery(rows[0]).parents('TABLE')[0];
        jQuery(rows).each(function(i, el) {
            if(el.id) {
                var newRow = jQuery(data).find('#'+el.id);
                jQuery('#'+el.id).replaceWith(newRow);
            }
        });
        applyRowStripes(table);
        ms_refresh_timer = window.setTimeout(function() {
            ms_refresh_timer = refresh_all_changed_rows();
        }, ms_row_refresh_interval)
    });
}

// used to update service status
function nc_omd_service(btn, extraData) {
    setBtnSpinner(btn, true);

    var form = jQuery(btn).parents('FORM');
    submitFormInBackground(form, function() {
        setBtnNoSpinner(btn);

        // update table row
        refresh_all_changed_rows_now();
    }, extraData);
}
