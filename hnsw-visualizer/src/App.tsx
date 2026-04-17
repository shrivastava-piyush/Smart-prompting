import { useState } from 'react'
import './App.css'
import { useHNSW } from './hooks/useHNSW'
import { GraphLayer } from './components/GraphLayer'
import { StackedGraph } from './components/StackedGraph'

function App() {
  const [M, setM] = useState(4);
  const [efConstruction, setEfConstruction] = useState(8);
  const { nodes, maxLevel, currentStep, isStepping, startAddPointStep, nextStep } = useHNSW({ M, efConstruction });
  const [currentLevel, setCurrentLevel] = useState(0);
  const [viewMode, setViewMode] = useState<'single' | 'stacked'>('single');

  const getStepDescription = (step: any) => {
    switch (step.type) {
      case 'search_layer_start': return `<strong>Greedy Search:</strong> Starting at node ${step.entryPoint} on Level ${step.level}. We jump to the neighbor closest to our target.`;
      case 'search_layer_step': return `<strong>Greedy Search:</strong> Scanning neighbors of ${step.current} on Level ${step.level}. Tracking ${step.candidates.length} closest candidates.`;
      case 'search_layer_end': return `<strong>Greedy Search:</strong> Level ${step.level} complete. Found nearest node ${step.nearest}. Moving down to next level.`;
      case 'connect_nodes': return `<strong>Heuristic Connection:</strong> Linking to neighbor ${step.nodeB} on Level ${step.level}.`;
      case 'shrink_neighbors': return `<strong>Diversity Heuristic:</strong> Limiting node ${step.node} connections on Level ${step.level} to keep search efficient.`;
      default: return '...';
    }
  };

  return (
    <div className="App">
      <header>
        <h1>HNSW Visualizer</h1>
        <p>Understand how vector databases navigate high-dimensional space.</p>
      </header>

      <div className="dashboard">
        <aside className="panel">
          <section>
            <h3>Controls</h3>
            <div className="controls">
              <button onClick={() => { const x = Math.random() * 700 + 50; const y = Math.random() * 400 + 50; startAddPointStep([x, y], Math.random().toString(36).substring(7)); }}>
                {isStepping ? "Select Point..." : "Add New Point"}
              </button>
              {isStepping && <button className="next-btn" onClick={nextStep}>Next Step</button>}
              <button style={{ backgroundColor: '#6c757d' }} onClick={() => setViewMode(viewMode === 'single' ? 'stacked' : 'single')}>
                View: {viewMode === 'single' ? 'Stacked' : 'Single'}
              </button>
            </div>
          </section>

          <section>
            <h3>Parameters</h3>
            <label>M (Max Neighbors): <input type="number" value={M} onChange={e => setM(Number(e.target.value))} /></label>
            <label>efConstruction: <input type="number" value={efConstruction} onChange={e => setEfConstruction(Number(e.target.value))} /></label>
          </section>
        </aside>
        
        <main className="graph-container">
          {viewMode === 'single' && (
            <div className="layer-selector">
              <label>Select Level: 
                <select value={currentLevel} onChange={(e) => setCurrentLevel(Number(e.target.value))}>
                  {Array.from({ length: Math.max(0, maxLevel + 1) }, (_, i) => <option key={i} value={i}>Level {i}</option>)}
                </select>
              </label>
            </div>
          )}
          {viewMode === 'single' ? 
            <GraphLayer nodes={nodes} level={currentLevel} width={800} height={500} currentStep={currentStep} onLayerClick={(x, y) => !isStepping && startAddPointStep([x, y], Math.random().toString(36).substring(7))} /> : 
            <StackedGraph nodes={nodes} maxLevel={maxLevel} width={800} height={500} />
          }
          {isStepping && currentStep && (
            <div className="explanation">
              <div className="step-counter">Current Algorithm Action:</div>
              <p dangerouslySetInnerHTML={{__html: getStepDescription(currentStep)}} />
            </div>
          )}
        </main>
      </div>
    </div>
  )
}
export default App
