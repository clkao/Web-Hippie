var Hippie = function(host, arg, onevent) {
    this.arg = arg;
    if ("WebSocket" in window) {
        this.ws = new WebSocket("ws://"+host+"/_hippie/ws/"+arg);
        this.ws.onmessage = function(ev) {
            var d = eval("("+ev.data+")");
            onevent(d);
        }
    }
    else if (typeof DUI != 'undefined') {
        var s = new DUI.Stream();
        s.listen('application/json', function(payload) {
            var event = eval('(' + payload + ')');
            onevent(event);
        });
        s.load("/_hippie/mxhr/"+arg);
        this.mxhr = s;
    }
    else {
        throw("not yet");
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