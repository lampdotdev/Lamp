/* An LG game's phones as controllers: the game's own service, packaged with it by Lamp (LGPhones.swift), so phones
 * play the game on the TV with the Mac asleep or gone. The game's page (lamp.js's Lamp.controllers) subscribes to
 * `start` as its controllers start, and gets back where its relay is and its host credential (relay.js); the session
 * lasts while that subscription does, so the game closing, or letting its controllers go, ends it, and the service
 * manager's own idle rule then ends the service. Nothing keeps it alive past that.
 *
 * Only the game this service was packaged with may start it or be given a host credential: a call from any other app
 * or service is turned away, whatever it asks.
 */
'use strict';
var path = require('path');
var Service = require('webos-service');
var relay = require('./relay');

var meta = require('./package.json').lamp;
var service = new Service(meta.service);
var session = new relay.Session({ root: path.join(__dirname, 'phone'), app: meta.app });
var subscribers = {};

function owner(message) { return message.sender === meta.owner; }
function respondAll() {
  var answer = session.answer();
  for (var token in subscribers) subscribers[token].respond(answer ? withResult(answer) : { returnValue: false, errorText: 'The game\'s phones stopped.' });
}
function withResult(answer) { answer.returnValue = true; return answer; }

// The TV's address moved, or the session had to start afresh: every subscriber hears where things are now.
session.onChange = function () {
  if (session.isRunning() || !Object.keys(subscribers).length) return respondAll();
  session.start(function () { respondAll(); });
};

service.register('start', function (message) {
  if (!owner(message)) return message.respond({ returnValue: false, errorText: 'Only this game may start its phones.' });
  if (!message.isSubscription) return message.respond({ returnValue: false, errorText: 'Subscribe to start the game\'s phones.' });
  subscribers[message.uniqueToken] = message;
  session.start(function (error, answer) {
    if (!subscribers[message.uniqueToken]) return;
    if (error) {
      delete subscribers[message.uniqueToken];
      return message.respond({ returnValue: false, errorText: error.message });
    }
    message.respond(withResult(answer));
  });
}, function (message) {
  // The game closed, or stopped its controllers: with nobody left holding it, the session ends, its sockets close and
  // its key is forgotten.
  delete subscribers[message.uniqueToken];
  if (!Object.keys(subscribers).length) session.stop();
});

// What the game's page asks again when its relay turned it away: the session's answer now, with a fresh credential.
service.register('session', function (message) {
  if (!owner(message)) return message.respond({ returnValue: false, errorText: 'Only this game may ask for its phones.' });
  var answer = session.answer();
  message.respond(answer ? withResult(answer) : { returnValue: false, errorText: 'The game\'s phones aren\'t started.' });
});
