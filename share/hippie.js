var Hippie = function(opt) {
    // Back-compat
    if (arguments.length > 1) {
        opt = {
            host:          arguments[0],
            arg:           arguments[1],
            on_connect:    arguments[2],
            on_disconnect: arguments[3],
            on_event:      arguments[4],
            path:          arguments[5],
        };
    }

    if (!opt) opt = {};

    this.on_disconnect = opt.on_disconnect ? opt.on_disconnect : function() {};
    this.on_connect    = opt.on_connect    ? opt.on_connect    : function() {};
    this.on_event      = opt.on_event      ? opt.on_event      : function() {};

    this.host      = opt.host ? opt.host : document.location.host;
    this.path      = opt.path ? opt.path : '';

    this.arg       = opt.arg    ? opt.arg    : '';
    this.params    = opt.params ? opt.params : '';

    this.detect();


    var that = this;
    if (this.mode == 'ws') {
        this.init = function() {
            if (!that.host.match('://'))
                that.host = document.location.protocol.replace(/http/, 'ws') + '//' + that.host;
            that.ws = new WebSocket(that.host+that.path+"/_hippie/ws/"+that.arg + that.params);
            that.ws.onmessage = function(ev) {
                var d = eval("("+ev.data+")");
                that.on_event(d);
            }
            that.ws.onclose = that.ws.onerror = function(ev) {
                that.on_disconnect();
            }
            that.ws.onopen = function() {
                that.on_connect();
            }
        };
    }
    else if (this.mode == 'mxhr') {
        this.init = function() {
            that.mxhr = new DUI.Stream();
            // XXX: somehow s.listeners are shared between objects.
            // maybe a DUI class issue?  this workarounds issue where
            // reconnect introduces duplicated listeners.
            that.mxhr.listeners = {};
            that.mxhr.listen('application/json', function(payload) {
                var d = eval('(' + payload + ')');
                that.on_event(d);
            });
            that.mxhr.listen('complete', function() {
                that.on_disconnect();
            });
            that.mxhr.load(that.path + "/_hippie/mxhr/" + that.arg + that.params);
            that.on_connect();
        };
    }
    else if (this.mode == 'poll') {
        this.init = function() {
            $.ev.loop(that.path + '/_hippie/poll/' + that.arg + that.params,
                      { '*': that.on_event }
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
    set_params: function(params) {
        this.params = params;
        if (this.mode == 'poll') {
            $.ev.url = this.path + '/_hippie/poll/' + this.arg + this.params;
        }
    },
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
                url: this.path + "/_hippie/pub/"+this.arg+this.params,
                data: { message: JSON.stringify(msg) },
                type: 'post',
                dataType: 'json',
                success: function(r) { }
            });
        }
    }
};
