Hippie.Pipe = function() {
};

Hippie.Pipe.prototype = {
    initial_reconnect: 5,
    init: function() {
        var self = jQuery(this);
        var that = this;
        this.reconnect_time = this.initial_reconnect;
        this.hippie = new Hippie( document.location.host, this.args,
                                  function() {
                                      self.trigger("connected");
                                  },
                                  function() {
                                      self.trigger("disconnected");
                                  },
                                  function(e) {
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

        self.bind("ready", function() { that.reconnect_time = that.initial_reconnect });
        self.bind("disconnected", function() {
            that.reconnect_timeout = window.setTimeout(try_reconnect, that.reconnect_time * 1000);
            self.trigger("reconnecting", { after: that.reconnect_time,
                                           try_now: function() { clearTimeout(that.reconnect_timeout); try_reconnect() } });
        });

    },
    send: function(msg) {
        this.hippie.send(msg);
    }
};
