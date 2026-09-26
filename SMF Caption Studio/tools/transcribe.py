#!/usr/bin/env python3
import argparse, json, os, sys, traceback

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('video')
    ap.add_argument('--model',default='small')
    ap.add_argument('--language',default='auto')
    args=ap.parse_args()

    try:
        from faster_whisper import WhisperModel
    except Exception as e:
        print(json.dumps({'error':'faster-whisper is not installed','detail':str(e)},ensure_ascii=False))
        sys.exit(2)

    try:
        device=os.environ.get('SMF_WHISPER_DEVICE','cpu')
        compute=os.environ.get('SMF_WHISPER_COMPUTE','int8')
        print('SMF_PROGRESS 3 | Loading Whisper runtime',file=sys.stderr,flush=True)
        model=WhisperModel(args.model,device=device,compute_type=compute)
        lang=None if args.language in ('','auto') else args.language
        print('SMF_PROGRESS 12 | Model loaded · transcribing audio',file=sys.stderr,flush=True)
        segments,info=model.transcribe(
            args.video,language=lang,word_timestamps=True,
            vad_filter=True,beam_size=5,condition_on_previous_text=True
        )
        out=[]
        total=float(os.environ.get('SMF_PROGRESS_DURATION','0') or 0)
        for seg in segments:
            words=[]
            for w in seg.words or []:
                word=(w.word or '').strip()
                if word:
                    words.append({
                        'word':word,'start':float(w.start),
                        'end':float(w.end),
                        'probability':float(getattr(w,'probability',0) or 0)
                    })
            out.append({
                'text':(seg.text or '').strip(),
                'start':float(seg.start),
                'end':float(seg.end),
                'words':words
            })
            if total>0:
                pct=min(98,max(12,(float(seg.end)/total)*82+12))
                print('SMF_PROGRESS %.1f | Transcribing · %.1fs' % (pct,float(seg.end)),file=sys.stderr,flush=True)
        print('SMF_PROGRESS 99 | Finalizing transcript',file=sys.stderr,flush=True)
        print(json.dumps({
            'language':info.language,
            'language_probability':float(getattr(info,'language_probability',0) or 0),
            'duration':float(getattr(info,'duration',0) or 0),
            'segments':out
        },ensure_ascii=False))
    except Exception as e:
        print('SMF_ERROR %s: %s' % (type(e).__name__,e),file=sys.stderr,flush=True)
        print(traceback.format_exc(),file=sys.stderr,flush=True)
        print(json.dumps({'error':str(e),'type':type(e).__name__},ensure_ascii=False))
        sys.exit(1)

if __name__=='__main__':
    main()
