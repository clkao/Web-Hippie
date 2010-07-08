var Hippie = function(host, arg, on_connect, on_disconnect, on_event, path) {

    this.arg = arg ? arg : '';
    this.on_disconnect = on_disconnect;
    this.on_connect = on_connect;
    this.on_event = on_event;
    this.path = path ? path : '';

    this.detect();

    var that = this;
    if (this.mode == 'ws') {
        this.init = function() {
            ws = new WebSocket("ws://"+host+that.path+"/_hippie/ws/"+that.arg + '?client_id=' + (that.client_id || ''));
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
    else if (this.mode == 'mxhr') {
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
            s.load(that.path + "/_hippie/mxhr/" + that.arg + '?client_id=' + (that.client_id || ''));
            that.on_connect();
            that.mxhr = s;
        };
    }
    else if (this.mode == 'poll') {
        this.init = function() {
            $.ev.loop(that.path + '/_hippie/poll/' + that.arg,
                      { '*': that.on_event,
                        'hippie.pipe.set_client_id': function(e) {
                            that.client_id = e.client_id;
                            $.ev.url = that.path + '/_hippie/poll/' + that.arg + '?client_id=' + e.client_id;
                            that.on_event(e);
                        }
                      }
                     );
            that.on_connect();
        }
    }
    else {
        throw new Error("unknown hippie mode: "+this.mode);
    }

    this.init();
};

Hippie.prototype = {
    detect: function() {
        var match = /hippie\.mode=(\w+)/.exec(document.location.search);
        if (match) {
            this.mode = match[1];
        }
        else {
            if ("WebSocket" in window) {
                this.mode = 'ws';
            }
            else {
                var req;
                try {
                    try { req = new ActiveXObject('MSXML2.XMLHTTP.6.0'); } catch(nope) {
                        try { req = new ActiveXObject('MSXML3.XMLHTTP'); } catch(nuhuh) {
                            try { req = new XMLHttpRequest(); } catch(noway) {
                                throw new Error('Could not find supported version of XMLHttpRequest.');
                            }
                        }
                    }
                }
                catch(e) {
                    this.mode = 'poll';
                    return;
                }

                this.mode = 'mxhr';
            }
        }
    },
    send: function(msg) {
        if (this.ws) {
            this.ws.send(JSON.stringify(msg));
        }
        else {
            var that = this;
            jQuery.ajax({
                url: this.path + "/_hippie/pub/"+this.arg,
                beforeSend: function(xhr, s) {
		    xhr.setRequestHeader("X-Hippie-ClientId", that.client_id);
                    return true;
                },
                data: { message: JSON.stringify(msg) },
                type: 'post',
                dataType: 'json',
                success: function(r) { }
            });
        }
    }
};
