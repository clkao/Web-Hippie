<html>
<head>
<title>Hippie Chat demo</title>
<script src="/static/jquery-1.3.2.min.js"></script>
<script src="/static/jquery.md5.js"></script>
<script src="/static/jquery.cookie.js"></script>
<script src="/static/pretty.js"></script>
<script>
var ws;
var cookieName = 'tatsumaki_chat_ident';

function doPost(el1, el) {
  var text = el.attr('value');
  location.href = 'http://' + location.host + '/chat/' + text;
  return;
}

$(function(){
    if ("WebSocket" in window) {
    }
    else {
        $("#content").text("This browser doesn't support WebSocket.");
        return;
    }
});
</script>
<link rel="stylesheet" href="/static/screen.css" />
<link rel="stylesheet" href="/static/chat.css" />
</head>
<body>

<div id="content">

<h1 class="chat-room-name">Enter room name:</h1>
<form onsubmit="doPost($('#ident'), $('#chat')); return false">
room name to enter: <input id="chat" type="text" size="48"/>
</form>

<table id="messages">
</table>

<div id="footer">Powered by <a href="http://github.com/clkao/Web-Hippie">Hippie/<?= $Web::Hippie::VERSION ?></a>.</div>

</div>
</body>
</html>
