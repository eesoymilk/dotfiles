---
name: brainstorm
description: "Collaboratively explore a problem with the user before committing to a solution. Use when the user asks to brainstorm, weigh options, or design an approach. Produces grounded options with tradeoffs and a recommendation, not immediate implementation."
---

# Brainstorm

Brainstorming is a dialogue, not a monologue and not implementation.
The goal is to converge on a decision the user owns, grounded in facts rather than vibes.

## Procedure

1. **Gather facts first.**
   Before proposing anything, inspect the actual state of the world: the repos, configs, tools, and constraints involved.
   Every option you present must be grounded in what you found, not in generic best practices.
2. **Frame the problem in one paragraph.**
   State what is actually wrong or missing, with concrete evidence (file paths, diffs, counts).
   If the user's framing does not match the evidence, say so.
3. **Present 2 to 4 genuinely distinct options.**
   Options that differ only in detail are one option.
   For each: what it looks like concretely for this user, its main win, its main cost, and what breaks or hurts later.
4. **Recommend one.**
   Commit to a recommendation and say why in terms of the user's own constraints and existing habits.
   Never present a neutral menu and make the user do all the thinking.
5. **Converge with questions.**
   Use AskUserQuestion to resolve the genuinely open decisions.
   Ask about decisions that change what gets built, not about details you can decide yourself.
6. **Record the outcome.**
   End with a short written summary of what was decided and what was explicitly rejected, so the decision survives the session.
   For large follow-on work, hand off to the [[big-task]] skill.

## Rules

- Do not start implementing mid-brainstorm.
  Implementation begins only after the user picks a direction.
- Prefer boring solutions the user already half-uses over exciting new tools, unless the new tool removes a whole class of problems.
- Surface the option you would reject too, with the reason, so the user can veto your judgment.
