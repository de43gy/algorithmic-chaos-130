use_bpm 130
use_debug false

set :global_tick, 0
set :section_tick, 0
set :lpf_control, 130

live_loop :global_timer do
  set :global_tick, get(:global_tick) + 1
  sleep 0.25
end

set :state, :intro

live_loop :conductor do
  puts "Current state: #{get(:state)}"
  set :section_tick, 0
  
  trans_time = 8
  
  case get(:state)
  when :intro
    sleep 16 - trans_time
    cue :transition_to_build_up
    sleep trans_time
    set :state, :build_up
    
  when :build_up
    sleep 32 - trans_time
    cue :transition_to_main_groove
    sleep trans_time
    set :state, :main_groove
    
  when :main_groove
    sleep 64 - trans_time
    cue :transition_to_breakdown
    sleep trans_time
    set :state, :breakdown
    
  when :breakdown
    sleep 32 - trans_time
    cue :transition_to_climax
    sleep trans_time
    set :state, :climax
    
  when :climax
    sleep 64 - trans_time
    cue :transition_to_intro
    sleep trans_time
    set :state, :intro
  end
end

live_loop :section_counter do
  set :section_tick, get(:section_tick) + 1
  sleep 0.25
end

live_loop :fx_automator do
  st = get(:state)
  sec_tick = get(:section_tick)
  
  target_cutoff = case st
  when :intro then 80
  when :build_up then line(80, 100, steps: 128).take(sec_tick).last || 100
  when :main_groove then 120
  when :breakdown then 90
  when :climax then line(120, 135, steps: 256).take(sec_tick).last || 135
  else 130
  end
  
  set :lpf_control, target_cutoff
  sleep 0.5
end

with_fx :compressor, threshold: 0.2, slope_above: 0.5, slope_below: 1, relax_time: 0.5 do
  with_fx :lpf, cutoff: 130 do |lpf_fx|
    with_fx :normaliser, level: 0.9 do
      
      live_loop :lpf_controller do
        control lpf_fx, cutoff: get(:lpf_control)
        sleep 0.25
      end
      
      live_loop :kick do
        st = get(:state)
        sec_tick = get(:section_tick)
        
        if st == :main_groove || st == :climax
          use_synth :bd_tek
          
          cutoff_evolution = 100
          if st == :main_groove && sec_tick
            cutoff_evolution = line(100, 130, steps: 256).take(sec_tick).last || 100
          end
          
          amp_val = (st == :climax) ? 1.9 : 1.6
          if st == :climax && sec_tick && sec_tick > 128
            sample :bd_tek, amp: amp_val * 1.1, cutoff: 140, lpf: 80 if one_in(3)
          end
          
          sample :bd_tek, amp: amp_val, cutoff: cutoff_evolution if (spread 5, 8).tick
        end
        sleep 0.25
      end
      
      # --- ТЕКСТУРА ---
      live_loop :glitch_hats do
        sync :kick
        st = get(:state)
        sec_tick = get(:section_tick)
        
        if st != :breakdown
          amp_mod = (st == :intro) ? 0.4 : 0.8
          amp_mod = (st == :climax) ? 1.0 : amp_mod
          
          density_mod = 1
          if st == :main_groove && sec_tick && sec_tick > 128
            density_mod = [1, 2].choose
          end
          
          density density_mod do
            sample :drum_cymbal_closed,
              amp: rrand(0.1, 0.3) * amp_mod,
              pan: rrand(-0.7, 0.7),
              rate: rrand(0.9, 1.1),
              finish: rrand(0.05, 0.2)
            
            sleep 0.125
            
            if one_in(6)
              sleep 0.125
            end
          end
        else
          sleep 0.125
        end
      end
      
      live_loop :atmosphere do
        st = get(:state)
        sec_tick = get(:section_tick)
        
        room_mod = 0.8 + (0.1 * Math.sin(get(:global_tick) * 0.01))
        mix_val = (st == :breakdown) ? 0.8 : 0.6
        
        with_fx :reverb, room: room_mod, mix: mix_val, damp: 0.5 do
          with_fx :panslicer, phase: 0.5, mix: 0.4, smooth: 0.1 do
            s = rrand(0.1, 0.6)
            f = s + rrand(0.01, 0.1)
            sample :ambi_drone,
              start: s, finish: f,
              rate: [-1, -0.5, 0.5, 1].choose,
              amp: 0.6, attack: 0.05, release: 0.1
          end
        end
        sleep 0.5
      end
      
      live_loop :bass do
        sync :kick
        st = get(:state)
        sec_tick = get(:section_tick)
        
        if st == :build_up || st == :main_groove || st == :climax
          use_synth :tb303
          
          notes = (scale :e1, :minor_pentatonic).shuffle.take(3).ring
          cutoff_mod = line(40, 120, steps: 8).tick
          
          amp_val = 1.0
          distort_val = 0.6
          if st == :build_up
            amp_val = 0.7
            distort_val = 0.3
          elsif st == :climax
            amp_val = 1.3
            distort_val = 0.8
          end
          
          if st == :main_groove && sec_tick
            distort_evolution = line(0.6, 0.85, steps: 256).take(sec_tick).last || 0.6
            distort_val = distort_evolution
          end
          
          res_min = 0.7
          res_max = 0.95
          if st == :climax && sec_tick
            res_min = line(0.7, 0.85, steps: 256).take(sec_tick).last || 0.7
            res_max = line(0.95, 0.98, steps: 256).take(sec_tick).last || 0.95
          end
          
          with_fx :distortion, distort: distort_val, mix: 0.5 do
            with_fx :echo, phase: 0.25, decay: 2, mix: 0.3 do
              if (spread 3, 7).tick
                play notes.look, release: 0.3, cutoff: cutoff_mod, res: rrand(res_min, res_max), amp: amp_val
              end
            end
          end
        end
        sleep 0.25
      end
      
      live_loop :evolving_lead do
        sync :atmosphere
        st = get(:state)
        sec_tick = get(:section_tick)
        
        if st == :build_up || st == :main_groove
          use_synth :fm
          
          seed = Time.now.to_i / 10
          use_random_seed seed
          
          base_notes = (scale :e3, :minor_pentatonic, num_octaves: 2)
          markov = [0, 2, -1, 3, 1, -2, 4].ring
          current = tick(:markov) % markov.length
          next_interval = markov[current]
          
          note_idx = (tick(:note) + next_interval) % base_notes.length
          current_note = base_notes[note_idx]
          
          mod_ratio = line(0.5, 8, steps: 32).look
          if st == :main_groove && sec_tick
            mod_evolution = line(1, 16, steps: 256).take(sec_tick).last || 1
            mod_ratio = mod_ratio * (mod_evolution / 8.0)
          end
          
          divisor = [0.125, 0.25, 0.5, 1].choose
          
          slicer_mix = rrand(0, 0.5)
          krush_mix = 0.3
          
          bits_min = 4
          bits_max = 16
          if st == :main_groove && sec_tick && sec_tick > 192
            bits_min = 2
            bits_max = 8
          end
          
          with_fx :krush, bits: rrand(bits_min, bits_max), cutoff: rrand(80, 120), mix: krush_mix do
            with_fx :slicer, phase: divisor, mix: slicer_mix do
              play current_note,
                divisor: mod_ratio,
                depth: rrand(1, 10),
                attack: rrand(0, 0.1),
                release: rrand(0.2, 1),
                cutoff: rrand(70, 110),
                amp: rrand(0.3, 0.6),
                pan: Math.sin(get(:global_tick) * 0.03)
            end
          end
        end
        
        sleep [0.25, 0.5, 0.125].choose
      end
      
      live_loop :metallic_percussion do
        sync :kick
        st = get(:state)
        
        if st != :intro
          perc_chance = (st == :climax) ? 2 : 4
          ping_chance = (st == :climax) ? 2 : 3
          
          if one_in(perc_chance)
            with_fx :ring_mod, freq: rrand(30, 60), mix: 0.7 do
              sample :perc_bell, rate: rrand(0.5, 2), amp: rrand(0.15, 0.35), pan: rrand(-1, 1), finish: 0.3
            end
          end
          
          if one_in(ping_chance)
            sample :elec_ping, rate: rrand(0.8, 1.5), amp: rrand(0.08, 0.2), pan: rrand(-0.5, 0.5)
          end
        end
        
        sleep 0.25
      end
      
      live_loop :chaos_bursts do
        st = get(:state)
        sec_tick = get(:section_tick)
        
        if st == :main_groove || st == :climax
          min_sleep = (st == :climax) ? 1 : 2
          max_sleep = (st == :climax) ? 4 : 8
          
          if st == :climax && sec_tick && sec_tick > 128
            min_sleep = 0.5
            max_sleep = 2
          end
          
          min_bits = (st == :climax) ? 1 : 2
          
          sleep rrand(min_sleep, max_sleep)
          
          with_fx :bitcrusher, bits: rrand(min_bits, 8), sample_rate: rrand(1000, 8000) do
            with_fx :reverb, room: 1, mix: 0.8 do
              burst_count = (st == :climax) ? 6 : 4
              if st == :climax && sec_tick && sec_tick > 192
                burst_count = rrand_i(8, 12)
              end
              
              burst_count.times do
                use_synth :noise
                play 60, release: 0.01, amp: rrand(0.2, 0.4), cutoff: rrand(60, 120), pan: rrand(-1, 1)
                sleep 0.0625
              end
            end
          end
        else
          sleep 1
        end
      end
      
      live_loop :morphing_drone do
        st = get(:state)
        sec_tick = get(:section_tick)
        
        if st == :breakdown || st == :climax
          use_synth :dark_ambience
          
          detune_amount = 0.1
          if st == :breakdown && sec_tick
            detune_amount = line(0.1, 0.5, steps: 128).take(sec_tick).last || 0.1
          end
          
          with_fx :reverb, room: 0.9, mix: 0.7 do
            with_fx :lpf, cutoff: rrand(60, 90) do
              play :e2, detune: detune_amount, release: 4, amp: 0.4, pan: Math.sin(get(:global_tick) * 0.01)
            end
          end
        end
        
        sleep 2
      end
      
      live_loop :microtonal_ghost do
        sync :kick
        st = get(:state)
        
        if st == :breakdown
          use_synth :prophet
          notes = (scale :e4, :major_blues, num_octaves: 2).shuffle
          
          with_fx :reverb, room: 0.9, mix: 0.8 do
            with_fx :pan, pan: Math.sin(get(:global_tick) * 0.05) do
              if (spread 7, 11).tick
                detune_val = rrand(-0.3, 0.3)
                play notes.look + detune_val, release: 0.2, cutoff: rrand(80, 110), amp: 0.6
              end
            end
          end
        end
        sleep 0.25
      end
      
      live_loop :climax_overload do
        sync :kick
        st = get(:state)
        
        if st == :climax
          if one_in(2)
            sample :glitch_perc1, rate: rrand(0.9, 1.1), amp: rrand(0.4, 0.8)
          end
          
          if one_in(3)
            sample :bd_haus, rate: 2, amp: 0.6, cutoff: 100
          end
        end
        sleep 0.125
      end
      
      live_loop :riser_to_main do
        sync :transition_to_main_groove
        in_thread do
          s = synth :cnoise, attack: 8, sustain: 0, release: 0.1, amp: 0.4, cutoff: 30
          32.times do
            control s, cutoff: (line 30, 130, steps: 32).tick, amp: (line 0.4, 1.0, steps: 32).look
            sleep 0.25
          end
        end
      end
      
      live_loop :fill_to_breakdown do
        sync :transition_to_breakdown
        in_thread do
          16.times do
            rate_val = (line 0.5, 2, steps: 16).tick
            sample :sn_dolf, rate: rate_val, amp: rrand(0.5, 0.8), pan: rrand(-0.5, 0.5)
            if one_in(3)
              with_fx :slicer, phase: 0.125 do
                sample :sn_dolf, rate: rate_val * 2, amp: 0.7
              end
            end
            sleep 0.5
          end
        end
      end
      
      live_loop :build_to_climax do
        sync :transition_to_climax
        in_thread do
          with_fx :echo, phase: (line 1, 0.125, steps: 16).ring.tick, decay: 4, mix: 0.7 do
            s = synth :saw, note: :e2, attack: 8, sustain: 0, release: 0.5, amp: 0.7
            16.times do
              control s, note: (line :e2, :e4, steps: 16).look
              sleep 0.5
            end
          end
        end
      end
      
      live_loop :fadeout_to_intro do
        sync :transition_to_intro
        in_thread do
          with_fx :reverb, room: 1, mix: 0.9 do
            with_fx :lpf, cutoff: (line 100, 40, steps: 8).tick do
              8.times do |i|
                with_fx :pitch_shift, pitch: -i * 2, mix: 0.6 do
                  sample :misc_crow, rate: rrand(0.1, 0.5), amp: line(0.6, 0, steps: 8)[i], pan: rrand(-1, 1)
                end
                sleep 1
              end
            end
          end
        end
      end
      
    end
  end
end