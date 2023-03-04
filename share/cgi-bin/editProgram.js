const d = document;

d.getElementById('buttonEraseId').addEventListener(
  'click',
  (event) => {
    d.getElementById('inputID').value = '';
  }
);