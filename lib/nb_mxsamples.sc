// nb mxsamples v1.0 - @sonoCircuit based on mx.samples @infinitedigits (thanks zack!)

NB_mxsamples {

	classvar <mxGroup, <mxBuffers;
	classvar <loadQueue, <loadingSamples = false;

	*addPlayer {

		if (mxGroup.isNil) {

			Routine.new({

				var s = Server.default;

				mxGroup = Group.new(s);

				s.sync;

				SynthDef(\mxPlayer, {
					arg out, sendABus, sendBBus, bfr,
					vel = 1, amp = 1, pan = 0, sendA = 0, sendB = 0, bndAmt = 1, bndDepth = 0,
					gate = 1, attack = 0.015, decay = 1, sustain = 1, release = 1.2,
					smpStart = 0, sampleEnd = 1, rate = 1, lpfHz = 20000, hpfHz = 20,
					modDepth = 0, lpfHzMod = 0, hpfHzMod = 0, sendAMod = 0, sendBMod = 0;

					var env, snd;

					// scale, clamp, smooth
					sendA = Lag.kr(sendA + (sendAMod * modDepth)).clip(0, 1);
					sendB = Lag.kr(sendB + (sendBMod * modDepth)).clip(0, 1);
					lpfHz = Lag.kr(lpfHz.cpsmidi + (lpfHzMod * modDepth * 127)).midicps.clip(20, 20000);
					hpfHz = Lag.kr(hpfHz.cpsmidi + (hpfHzMod * modDepth * 127)).midicps.clip(20, 20000);
					rate = Lag.kr(BufRateScale.ir(bfr) * rate * (bndAmt * bndDepth).midiratio);

					// env
					env = EnvGen.ar(Env.new([0, 1, sustain, 0], [attack + 0.015, decay, release], 'cubed', 2), gate, doneAction: 2);

					// sound
					snd = PlayBuf.ar(2, bfr, rate, startPos: smpStart * 48000);
					snd = LPF.ar(snd, lpfHz);
					snd = HPF.ar(snd, hpfHz);
					snd = Balance2.ar(snd[0], snd[1], pan);
					snd = snd * amp * vel * env;

					DetectSilence.ar(snd, doneAction: 2);

					Out.ar(sendABus, snd * sendA);
					Out.ar(sendBBus, snd * sendB);
					Out.ar(out, snd)
				}).add;

			}).play;

		}

	}

	*queueLoadSample { arg buf, path;
		var t = (buf: buf, path: path);
		loadQueue = loadQueue.addFirst(t);
		if (loadingSamples.not) { NB_mxsamples.loadSample() };
	}

	*clearSample { arg buf;
		if (mxBuffers[buf].notNil) {
			if (mxBuffers[buf].bufnum.notNil) { mxBuffers[buf].free };
			mxBuffers[buf] = nil;
		};
	}

	*loadSample {
		var t;
		if (loadQueue.notEmpty) {
			t = loadQueue.pop;
			loadingSamples = true;
			NB_mxsamples.clearSample(t.buf);
			mxBuffers[t.buf] = Buffer.read(Server.default, t.path, action: { NB_mxsamples.loadSample() });
			//("loaded..." + t.buf + t.path).postln;
		}{
			loadingSamples = false;
		};
	}

	*initClass {

		var mxVoices, voiceParams;
		var numVoices = 12;
		var numBuffers = 80;

		StartUp.add {

			voiceParams = Dictionary.newFrom([
				\bndAmt, 1,
				\amp, 0.8,
				\pan, 0,
				\sendA, 0,
				\sendB, 0,
				\smpStart, 0,
				\attack, 0,
				\decay, 0.2,
				\sustain, 1,
				\release, 1.2,
				\lpfHz, 20000,
				\hpfHz, 20,
				\lpfHzMod, 0,
				\hpfHzMod, 0,
				\sendAMod, 0,
				\sendBMod, 0
			]);

			mxVoices = Array.newClear(numVoices);
			mxBuffers = Array.newClear(numBuffers);
			loadQueue = Array.new(numBuffers);

			// osc functions
			OSCFunc.new({ |msg|
				if (mxGroup.isNil) {
					NB_mxsamples.addPlayer();
					"nb mxsamples initialzed".postln;
				};
			}, "/nb_mxsamples/init");

			OSCFunc.new({ |msg|
				var vox = msg[1].asInteger;
				var buf = msg[2].asInteger;
				var rate = msg[3].asFloat;
				var vel = msg[4].asFloat;
				var syn;
				if (mxBuffers[buf].notNil) {
					if (mxVoices[vox].notNil) { mxVoices[vox].set(\gate, -1.05) };
					syn = Synth.new(\mxPlayer,
						[
							\bfr, mxBuffers[buf],
							\rate, rate,
							\vel, vel,
							\sendABus, ~sendA ? Server.default.outputBus,
							\sendBBus, ~sendB ? Server.default.outputBus,
						] ++ voiceParams.getPairs, target: mxGroup
					);
					mxVoices[vox] = syn;
					syn.onFree({ if (mxVoices[vox] === syn) {mxVoices[vox] = nil} });
				};
			}, "/nb_mxsamples/note_on");

			OSCFunc.new({ |msg|
				var vox = msg[1].asInteger;
				if (mxVoices[vox].notNil) { mxVoices[vox].set(\gate, 0) }
			}, "/nb_mxsamples/note_off");

			OSCFunc.new({ |msg|
				if (mxGroup.notNil) { mxGroup.set(\gate, -1.05) }
			}, "/nb_mxsamples/panic");

			OSCFunc.new({ |msg|
				var key = msg[1].asSymbol;
				var val = msg[2].asFloat;
				if (mxGroup.notNil) {
					mxGroup.set(key, val);
				};
				voiceParams[key] = val;
			}, "/nb_mxsamples/set_param");

			OSCFunc.new({ |msg|
				loadQueue = Array.new(numBuffers);
				loadingSamples = false;
			}, "/nb_mxsamples/reset_loadqueue");

			OSCFunc.new({ |msg|
				var buf = msg[1].asInteger;
				var path = msg[2].asString;
				NB_mxsamples.queueLoadSample(buf, path)
			}, "/nb_mxsamples/load_sample");

			OSCFunc.new({ |msg|
				var buf = msg[1].asInteger;
				NB_mxsamples.clearSample(buf)
			}, "/nb_mxsamples/clear_sample");

			OSCFunc.new({ |msg|
				numBuffers.do({ |buf|
					NB_mxsamples.clearSample(buf)
				});
				"nb mxsamples buffers freed".postln;
			}, "/nb_mxsamples/free_buffers");

			OSCFunc.new({ |msg|
				numBuffers.do({ |buf|
					NB_mxsamples.clearSample(buf)
				});
				mxGroup.free;
				"nb mxsamples freed".postln;
			}, "/nb_mxsamples/free_all");

		}
	}
}
