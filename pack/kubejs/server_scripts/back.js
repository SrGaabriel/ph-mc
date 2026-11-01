// /back: teleport once to where you last died, so a death deep in a cave doesn't mean the long walk back.
// It only ever goes to your death spot (useless as a free teleport otherwise), only once per death,
// and only for a few minutes. You still have to fight or dig your way out after.

const BACK_WINDOW_MINUTES = 10;

// Death spots live in the server's persistent data, keyed by UUID: "dimension|x|y|z|time"
const backKey = (uuid) => "ph_back_" + uuid;

function uuidOf(entity) {
  return String(entity.stringUuid || entity.uuid);
}

function backDimension(level) {
  return String(level.dimension);
}

EntityEvents.death((event) => {
  const entity = event.entity;
  if (!entity.isPlayer()) return;
  const level = event.level;
  // Void deaths: there's nothing to go back to, and you'd fall again
  if (entity.y < level.minBuildHeight) return;
  const spot = [
    backDimension(level),
    entity.x,
    entity.y,
    entity.z,
    Date.now(),
  ].join("|");
  event.server.persistentData.putString(backKey(uuidOf(entity)), spot);
});

PlayerEvents.respawned((event) => {
  const player = event.player;
  if (!event.server.persistentData.contains(backKey(uuidOf(player)))) return;
  player.tell(
    Text.gray("Type ")
      .append(Text.yellow("/back"))
      .append(
        Text.gray(
          " within " +
            BACK_WINDOW_MINUTES +
            " minutes to return to where you died, once.",
        ),
      ),
  );
});

ServerEvents.commandRegistry((event) => {
  const { commands: Commands } = event;
  event.register(
    Commands.literal("back").executes((ctx) => {
      const player = ctx.source.getPlayerOrException();
      const server = player.server;
      const data = server.persistentData;
      const key = backKey(uuidOf(player));

      if (!data.contains(key)) {
        player.tell(Text.red("Nowhere to go back to."));
        return 0;
      }
      const [dim, x, y, z, time] = String(data.getString(key)).split("|");
      if (Date.now() - Number(time) > BACK_WINDOW_MINUTES * 60 * 1000) {
        data.remove(key);
        player.tell(
          Text.red(
            "Too late: /back only works for " +
              BACK_WINDOW_MINUTES +
              " minutes after dying.",
          ),
        );
        return 0;
      }

      data.remove(key);
      const who = uuidOf(player);
      server.runCommandSilent(`execute in ${dim} run tp ${who} ${x} ${y} ${z}`);
      // You died here once already: a few seconds of grace against the lava or fall that did it
      server.runCommandSilent(
        `effect give ${who} minecraft:fire_resistance 20 0 true`,
      );
      server.runCommandSilent(
        `effect give ${who} minecraft:slow_falling 10 0 true`,
      );
      server.runCommandSilent(
        `effect give ${who} minecraft:water_breathing 20 0 true`,
      );
      player.tell(Text.green("Back where you died."));
      return 1;
    }),
  );
});
