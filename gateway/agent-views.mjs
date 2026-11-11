const empty = { type: 'object', properties: {}, additionalProperties: false };
export const viewTools = [
  { name: 'look_at_world', description: 'See the most recent Euclid world screenshot the player shared with you. It expires after five minutes.',
    inputSchema: empty },
  { name: 'view_check_capture', description: 'See a rendered screenshot attached to your current checked draft. Find available views in draft_status.',
    inputSchema: { type: 'object', properties: { view: { type: 'string', maxLength: 64 } }, required: ['view'], additionalProperties: false } },
];

export function createAgentViews() {
  const views = new Map();
  return {
    share({ to, zone, image }) {
      if (typeof to !== 'string' || !/^[a-z0-9_-]{1,32}$/.test(to)) throw new Error('Choose a named agent.');
      if (typeof image !== 'string' || image.length > 360000 || !/^[A-Za-z0-9+/]+={0,2}$/.test(image)) {
        throw new Error('Expected a small JPEG screenshot.');
      }
      const data = Buffer.from(image, 'base64');
      if (data.length < 4 || data[0] !== 0xff || data[1] !== 0xd8 || data.at(-2) !== 0xff || data.at(-1) !== 0xd9) {
        throw new Error('Expected a JPEG screenshot.');
      }
      views.delete(to);
      if (views.size >= 24) views.delete(views.keys().next().value);
      views.set(to, { image, zone: String(zone ?? '').slice(0, 80), at: Date.now() });
      return { ok: true, to };
    },
    look(agent) {
      const view = views.get(agent);
      if (!view || Date.now() - view.at > 300000) {
        views.delete(agent);
        throw new Error('Ask the player to share the current view with /share-view in F2.');
      }
      return { ok: true, message: `Shared view of ${view.zone} from ${new Date(view.at).toISOString()}.`, image: view.image };
    },
  };
}
