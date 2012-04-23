Hippie.Pipe = function() {
};

Hippie.Pipe.prototype = {
    initial_reconnect: 5,
    init: function(opt) {
        var self = jQuery(this);
        var that = this;
        if (!opt) opt = {}
        if (!opt.host)
            opt.host = document.location.host;
        this.reconnect_time = this.initial_reconnect;
        this.hippie = new Hippie( opt.host, this.args,
                                  function() {
				      self.trigger("connected");
				      that.flushQueue();
                                  },
                                  function() {
                                      self.trigger("disconnected");
                                  },
                                  function(e) {
                                      self.trigger("message.*", e);
                                      if (e.type == "hippie.pipe.set_client_id") {
                                          self.trigger("ready", e.client_id);
                                      }
                                      else {
                                          self.trigger("message."+e.type, e);
                                      }
                                  });


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
