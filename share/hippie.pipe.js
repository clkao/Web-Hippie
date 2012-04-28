Hippie.Pipe = function(opt) {
    if (!opt) opt = {}

    this.opt = opt;
};

Hippie.Pipe.prototype = {
    initial_reconnect: 5,
    init: function() {
        // back-compat
        if (arguments.length)
            this.opt = arguments[0];

        var self = jQuery(this);
        var that = this;
        var params = ''
        if (this.opt.client_id) {
            params = '?client_id='+this.opt.client_id;
        }

        this.reconnect_time = this.initial_reconnect;
        this.hippie = new Hippie( {
            host:      this.opt.host,
            path:      this.opt.path,
            arg:       this.opt.arg,
            params:    params,
            on_connect:    function() {
                self.trigger("connected");
                that.flushQueue();
            },
            on_disconnect: function() { self.trigger("disconnected"); },
            on_event:      function(e) {
                if (e.type == "hippie.pipe.set_client_id") {
                    that.opt.client_id = e.client_id;
                    that.hippie.set_params('?client_id='+e.client_id);
                    self.trigger("ready", e.client_id);
                }
                else {
                    self.trigger("message."+e.type, e);
                    self.trigger("message.*", e);
                }
            } } );

        var try_reconnect = function() {
            that.hippie.init();
            that.reconnect_time *= 2;
        };

        self.bind("ready", function() {
	    that.reconnect_time = that.initial_reconnect;
	    that.flushQueue();
    	});
        self.bind("disconnected", function() {
            that.reconnect_timeout = window.setTimeout(try_reconnect, that.reconnect_time * 1000);
            self.trigger("reconnecting", { after: that.reconnect_time,
                                           try_now: function() { clearTimeout(that.reconnect_timeout); try_reconnect() } });
        });

    },
    send: function(msg) {
	if (! this.sendQ) this.sendQ = [];
	this.sendQ.push(msg);
	this.flushQueue();
    },
    flushQueue: function () {
	var self = this;
	if (! this.sendQ) return;
	if (! this.hippie) {
            // try again soon
	    window.setTimeout(function () { self.flushQueue() }, 1000);
	    return;
	}
	for (var i = 0; i < this.sendQ.length; i++) {
            this.hippie.send(this.sendQ[i]);
	}
	this.sendQ = [];
    }
};
