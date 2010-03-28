var Hippie = function(host, arg, on_connect, on_disconnect, on_event) {

    this.arg = arg;
    this.on_disconnect = on_disconnect;
    this.on_connect = on_connect;
    this.on_event = on_event;

    if ("WebSocket" in window) {
        var that = this;
        this.init = function() {
            ws = new WebSocket("ws://"+host+"/_hippie/ws/"+arg + '?client_id=' + (that.client_id || ''));
            ws.onmessage = function(ev) {
                var d = eval("("+ev.data+")");
                if (d.type == "hippie.pipe.set_client_id") {
                    that.client_id = d.client_id;
                }
                that.on_event(d);
            }
            ws.onclose = ws.onerror = function(ev) {
                that.on_disconnect();
            }
            ws.onopen = function() {
                that.on_connect();
            }
            that.ws = ws;
        };
    }
    else if (typeof DUI != 'undefined') {
        var that = this;
        this.init = function() {
            var s = new DUI.Stream();
            // XXX: somehow s.listeners are shared between objects.
            // maybe a DUI class issue?  this workarounds issue where
            // reconnect introduces duplicated listeners.
            s.listeners = {};
            s.listen('application/json', function(payload) {
                var event = eval('(' + payload + ')');
                if (event.type == "hippie.pipe.set_client_id") {
                    that.client_id = event.client_id;
                }
                that.on_event(event);
            });
            s.listen('complete', function() {
                that.on_disconnect();
            });
            s.load("/_hippie/mxhr/" + arg + '?client_id=' + (that.client_id || ''));
            that.on_connect();
            that.mxhr = s;
        };
    }
    else {
        var that = this;
        this.init = function() {
            $.ev.loop('/_hippie/poll/' + arg,
                      { '*': that.on_event,
                        'hippie.pipe.set_client_id': function(e) {
                            that.client_id = e.client_id;
                            $.ev.url = '/_hippie/poll/' + arg + '?client_id=' + e.client_id;
                            that.on_event(e);
                        }
                      }
                     );
            that.on_connect();
        }
    }

    this.init();
};

Hippie.prototype = {
    send: function(msg) {
        if (this.ws) {
            this.ws.send(JSON.stringify(msg));
        }
        else {
            var that = this;
            jQuery.ajax({
                url: "/_hippie/pub/"+this.arg,
                beforeSend: function(xhr, s) {
		    xhr.setRequestHeader("X-Hippie-ClientId", that.client_id);
                    return true;
                },
                data: msg,
                type: 'post',
                dataType: 'json',
                success: function(r) { }
            });
        }
    }
};
