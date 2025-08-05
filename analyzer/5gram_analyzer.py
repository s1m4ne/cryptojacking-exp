import sys
import json
from collections import deque, Counter

N_GRAM_SIZE = 5
TOP_N_RESULTS = 20

def main():
    window = deque(maxlen=N_GRAM_SIZE)
    ngram_counts = Counter()
    
    print("[INFO] Final analysis script started.", file=sys.stderr)
    print("[INFO] Silently counting n-grams in the background...", file=sys.stderr)
    print("[INFO] Press Ctrl+C to stop and see the final ranking.", file=sys.stderr)
    
    try:
        for line in sys.stdin:
            try:
                event = json.loads(line)
                
                if (trace_point := event.get('process_tracepoint')) and \
                   trace_point.get('event') == 'sys_enter':
                    
                    args = trace_point.get('args', [])
                    syscall_num = None
                    
                    if len(args) > 0:
                        arg_obj = args[0]
                        if 'int_arg' in arg_obj:
                            syscall_num = arg_obj.get('int_arg')
                        elif 'long_arg' in arg_obj:
                            syscall_num = int(arg_obj.get('long_arg'))
                    
                    if syscall_num is not None:
                        window.append(syscall_num)
                        if len(window) == N_GRAM_SIZE:
                            ngram = tuple(window)
                            ngram_counts[ngram] += 1
                            
            except (json.JSONDecodeError, AttributeError, ValueError, KeyError, IndexError):
                continue
                
    except KeyboardInterrupt:
        print("\n[INFO] Script interrupted. Calculating final frequencies...", file=sys.stderr)
        
    finally:
        print_results(ngram_counts)

def print_results(counter):
    print("\n" + "="*50)
    print(f"     Top {TOP_N_RESULTS} most common {N_GRAM_SIZE}-grams")
    print("="*50)
    
    if not counter:
        print("No n-grams were generated.")
        print("Possible reasons:")
        print("  - The target container did not run or produce syscalls.")
        print("  - The TracingPolicy's podSelector does not match the container's labels.")
    else:
        for ngram, count in counter.most_common(TOP_N_RESULTS):
            print(f"Count: {count:<7} | n-gram: {ngram}")
    
    print("="*50)
    print("Analysis finished.")

if __name__ == '__main__':
    main()
