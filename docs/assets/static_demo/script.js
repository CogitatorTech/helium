function testScript() {
  const output = document.getElementById('output');
  output.innerHTML = '<strong>JavaScript is working!</strong><br>' +
    'File served from: /script.js<br>' +
    'Current time: ' + new Date().toLocaleString();
  output.style.background = '#d4edda';
  output.style.color = '#155724';
  output.style.border = '1px solid #c3e6cb';
}

console.log('Static JavaScript file loaded successfully!');