var Hippie = function(host, arg, on_connect, on_disconnect, on_event, reconnect_time) {

    this.arg = arg;
    this.on_disconnect = on_disconnect;
    this.on_connect = on_connect;
    this.on_event = on_event;
    this.reconnect_time = reconnect_time;

    if ("WebSocket" in window) {
        var that = this;
        this.init = function() {
            ws = new WebSocket("ws://"+host+"/_hippie/ws/"+arg);
            ws.onmessage = function(ev) {
                var d = eval("("+ev.data+")");
                that.on_event(d);
            }
            ws.onclose = ws.onerror = function(ev) {
                that.on_disconnect();
            }
            ws.onopen = function() {
                that.on_connect();
                that.reconnect_time = reconnect_time;
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
                that.on_event(event);
            });
            s.listen('complete', function() {
                that.on_disconnect();
            });
            s.load("/_hippie/mxhr/"+arg);
            that.on_connect();
            that.reconnect_time = reconnect_time; // XXX: this is not really correct, need onready hook from xmhr.
            that.mxhr = s;
        };
    }
    else {
        throw("not yet");
    }

    this.init();
    if (reconnect_time) {
        var disconnect = this.on_disconnect;
        var that = this;
        var try_reconnect = function() {
            that.init();
            that.reconnect_time *= 2;
        };
    
        this.on_disconnect = function() {
            that.reconnect_timeout = window.setTimeout(try_reconnect, that.reconnect_time * 1000);
            disconnect();
        };
        this.reconnect_now = function() {
            if (that.reconnect_timeout) {
                clearTimeout(that.reconnect_timeout);
                try_reconnect();
            }
        }
    }
};

Hippie.prototype = {
    send: function(msg) {
        if (this.ws) {
            this.ws.send(JSON.stringify(msg));
        }
        else if (this.mxhr) {
            jQuery.ajax({
                url: "/_hippie/pub/"+this.arg,
                data: msg,
                type: 'post',
                dataType: 'json',
                success: function(r) { }
            });
        }
    }
};
