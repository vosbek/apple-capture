---
schema: qcon.brief/1
talk_id: <talk_id from talk.json>
title: <title>
speakers: [{ name: <name>, company: <company>, role: <role> }]
event: QCon San Francisco 2026
date: <YYYY-MM-DD, conference-local>
kind: <keynote | presentation | sponsored | training | unconference | adhoc>
track: <track name or null>
talk_url: <qconsf.com URL or null>
official_video: { status: pending, url: null, video_offset_ms: null }
official_slides: null
capture: { photos: 0, moments: 0, notes: 0, reflections: 0, session_audio: none, devices: [iphone], start_synced: false }
confidence: <high | medium | low>
confidence_reason: <one sentence: how well this brief represents the talk>
lenses: []
tags: []
visibility: <shareable | private, from talk.json>
status: draft            # draft | reviewed | published
reviewed_by: null
updated: <YYYY-MM-DD>
---

## In one paragraph
What the talk argued and why it matters to us. Four sentences at most.

## Key ideas
1. Idea, in one or two sentences, with capture marks.
(three to six items)

## Evidence
- What the speaker showed: data, architecture, demo. With marks.
- What public sources confirm or contradict. With marks.
- What we could not verify.

## How we could use it
### <lens name>
- The move: what we would change or try.
- First step: the smallest experiment, who would run it, rough size (S, M, L).
- Needs: prerequisites and dependencies.
- Risk or reason it may not transfer.
(one block per lens that fits, three at most; "No clear fit" is an acceptable answer)

## Follow-ups
- People to contact, repos to try, questions left open.

## Watch list
Filled by the reconcile pass: video timestamps for each moment.

## Sources
R1 … with URL and fetch date. Slide photos referenced are in assets/.
