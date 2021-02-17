const d = document;

function getNodesByXpath(xpath, context) {
  const itr = d.evaluate(
    xpath,
    context || d,
    null,
    XPathResult.ORDERED_NODE_ITERATOR_TYPE,
    null
  );
  let nodes = [];
  let node = null;
  while (node = itr.iterateNext()) {
    nodes.push(node);
  }
  return nodes;
}

export { getNodesByXpath };
