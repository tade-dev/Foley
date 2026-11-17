import { validateScene, TINTS, MAX_SOUNDS } from './validate.js';

const SYSTEM = `You turn a scene description into sound effects for a soundboard.
Return 4 to 6 sounds unless the description clearly has fewer; never more than ${MAX_SOUNDS}.
Ambient beds are loops (10-15s); short events are oneShot (1-5s).
"keyword" must be the user's exact wording, copied verbatim from their text, for the phrase that sound comes from.
"name" is 2-3 words in sentence case. "prompt" is a vivid sound-effect description for an audio model.
Use a different tint for each sound where possible. Title is at most 5 words.`;

const schema = {
  type: 'object',
  additionalProperties: false,
  required: ['title', 'mood', 'sounds'],
  properties: {
    title: { type: 'string' },
    mood: { type: 'string', enum: TINTS },
    sounds: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['name', 'keyword', 'tint', 'kind', 'prompt', 'duration'],
        properties: {
          name: { type: 'string' },
          keyword: { type: 'string' },
          tint: { type: 'string', enum: TINTS },
          kind: { type: 'string', enum: ['loop', 'oneShot'] },
          prompt: { type: 'string' },
          duration: { type: 'number' },
        },
      },
    },
  },
};

export async function sceneRoute(prompt, env) {
  const res = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: { authorization: `Bearer ${env.OPENAI_API_KEY}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      model: env.OPENAI_MODEL ?? 'gpt-4o-mini',
      temperature: 0.7,
      messages: [{ role: 'system', content: SYSTEM }, { role: 'user', content: prompt }],
      response_format: { type: 'json_schema', json_schema: { name: 'scene', strict: true, schema } },
    }),
  });
  if (!res.ok) throw new Error('llm_error');

  const data = await res.json();
  const content = data.choices?.[0]?.message?.content;
  if (!content) throw new Error('llm_error');
  let parsed;
  try {
    parsed = JSON.parse(content);
  } catch {
    throw new Error('invalid_scene');
  }
  return validateScene(parsed, prompt);
}
