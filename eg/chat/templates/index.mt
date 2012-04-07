<html>
<head>
<title>Hippie Chat demo</title>
<script src="/static/jquery-1.3.2.min.js"></script>
<script src="/static/jquery.md5.js"></script>
<script src="/static/jquery.cookie.js"></script>
<script src="/static/pretty.js"></script>
<script>
function doPost(el) {
  location.href = 'http://' + location.host + '/chat/' + el.attr('value');
  return;
}
</script>
<link rel="stylesheet" href="/static/screen.css" />
<link rel="stylesheet" href="/static/chat.css" />
</head>
<body>

<div id="content">

<h1 class="chat-room-name">Enter room name:</h1>
<form onsubmit="doPost($('#chat')); return false">
room name to enter: <input id="chat" type="text" size="48"/>
</form>

<table id="messages">
</table>

<div id="footer">Powered by <a href="http://github.com/clkao/Web-Hippie">Hippie/<?= $Web::Hippie::VERSION ?></a>.</div>

</div>
</body>
</html>
