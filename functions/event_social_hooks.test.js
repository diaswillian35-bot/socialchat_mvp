"use strict";
const assert = require("assert");
const { socialInputsChanged, SOCIAL_TRIGGER_FIELDS } = require("./event_social_hooks");

assert.ok(SOCIAL_TRIGGER_FIELDS.includes("coverUrl"));
assert.strictEqual(socialInputsChanged(null, { title: "A" }), true);
assert.strictEqual(
  socialInputsChanged({ title: "A", city: "X" }, { title: "A", city: "X" }),
  false,
);
assert.strictEqual(
  socialInputsChanged({ title: "A" }, { title: "B" }),
  true,
);
console.log("PASS event_social_hooks");
