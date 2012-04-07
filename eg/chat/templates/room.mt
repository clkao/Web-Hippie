? my ($env, $host, $room) = @_;
<html>
<head>
<title>Hippie Chat demo</title>
<script src="/static/jquery-1.3.2.min.js"></script>
<script src="/static/jquery.md5.js"></script>
<script src="/static/jquery.cookie.js"></script>
<script src="/static/pretty.js"></script>

? if ($env->{'psgix.jsconcat.url'}) {
<script src="<?= $env->{'psgix.jsconcat.url'} ?>"></script>
? }
? else {
<script src="/static/jquery.ev.js"></script>

<script src="/static/DUI.js"></script>
<script src="/static/Stream.js"></script>

<script src="/static/hippie.js"></script>
<script src="/static/hippie.pipe.js"></script>

<script src="/static/json2.js"></script>

? }

<script>
var hpipe;
var cookieName = 'tatsumaki_chat_ident';

function doPost(el1, el) {
  var ident = el1.attr('value');
  if (ident) $.cookie(cookieName, ident, { path: '/chat' });
  var text = el.attr('value');
  if (!text) return;

  hpipe.send({ type: 'message', room: "<?= $room ?>", ident:ident, text:text });
  el.attr('value', '');
  return;
}

$(function(){
    var timer_update;
    hpipe = new Hippie.Pipe( {arg: "<?= $room ?>"} );

    var status = $('#connection-status');
    jQuery(hpipe)
        .bind("connected", function () {
            status.addClass("connected").text("Connected");
            if(timer_update) clearTimeout(timer_update);
        })
        .bind("disconnected", function() {
            status.removeClass("connected").text("Server disconnected. ");
        })
        .bind("reconnecting", function(e, data) {
            var retry = new Date(new Date().getTime()+data.after*1000);
            var try_now = $('<span/>').text("Try now").click(data.try_now);
            var timer = $('<span/>');
            var do_timer_update = function() {
                timer.text( Math.ceil((retry - new Date())/1000) + "s. " )
                timer_update = window.setTimeout( do_timer_update, 1000);
            };
            status.text("Server disconnected.  retry in ").append(timer).append(try_now);
            do_timer_update();
        })
        .bind("message.message", function (e, d) {
            try {
                var src = d.avator || ("http://www.gravatar.com/avatar/" + $.md5(d.ident || 'foo'));
                var name = d.name || d.ident || 'Anonymous';
                var avatar = $('<img/>').attr('src', src).attr('alt', name);
                if (d.ident) {
                    var link = d.ident.match(/https?:/) ? d.ident : 'mailto:' + d.ident;
                    avatar = $('<a/>').attr('href', link).attr('target', '_blank').append(avatar);
                }
                avatar = $('<td/>').addClass('avatar').append(avatar);

                var message = $('<td/>').addClass('chat-message');
                if (d.text) message.text(d.text);
                if (d.html) message.html(d.html);

                var name = d.name || (d.ident ? d.ident.split('@')[0] : null);
                if (name)
                    message.prepend($('<span/>').addClass('name').text(name+': '));

                var date = new Date(d.time * 1000);
                var meta = $('<td/>').addClass('meta').append(
                    '(' +
                        '<span class="pretty-time" title="' + date.toUTCString() + '">' + date.toDateString() + '</span>' +
                        ' from ' + d.address + ')'
                );
                $('.pretty-time', meta).prettyDate();
                $('#messages').prepend($('<tr/>').addClass('message').append(avatar).append(message).append(meta));

            } catch(e) { if (console) console.log(e) }
        });
    hpipe.init();
    if ($.cookie(cookieName))
        $('#ident').attr('value', $.cookie(cookieName));

    window.setInterval(function(){ $(".pretty-time").prettyDate() }, 1000 * 30);
});
</script>
<link rel="stylesheet" href="/static/screen.css" />
<link rel="stylesheet" href="/static/chat.css" />
</head>
<body>

<h1 class="chat-room-name">Chat room: <?= $room ?></h1>
<!-- move this input out of form so Firefox can submit with enter key :/ -->
Your email (for Gravatar): <input id="ident" type="text" name="ident" size="24"/>
<form onsubmit="doPost($('#ident'), $('#chat')); return false">
Something to say: <input id="chat" type="text" size="48"/>
</form>

<div id="connection-status" class="disconnected">
Connecting...
</div>

<table id="messages">
</table>

<div id="footer">Powered by <a href="http://github.com/clkao/Web-Hippie">Hippie/<?= $Web::Hippie::VERSION ?></a>.</div>

</body>
</html>
