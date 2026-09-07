/* elm-pkg-js
port telemetry_read : ( Int, Bool ) -> Cmd msg
import Json.Encode
port telemetry_observed : (Json.Encode.Value -> msg) -> Sub msg
*/
exports.init = async function(app) {
  window.__uqmTelemetryDispose?.();
  const read = ([serial, returning]) => app.ports.telemetry_observed?.send([serial, returning, performance.now()]);
  app.ports.telemetry_read?.subscribe(read);
  window.__uqmTelemetryDispose = () => app.ports.telemetry_read?.unsubscribe(read);
};
