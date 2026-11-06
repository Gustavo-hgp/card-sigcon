'use strict';
// card-sigcon - pagina local. Fala com ui/servidor.ps1; quem roda o Kiro e o card.ps1 e o servidor.

const TOKEN = window.CARD_SIGCON_TOKEN;
const $ = (s) => document.querySelector(s);
const $$ = (s, raiz) => Array.from((raiz || document).querySelectorAll(s));

let estado = null;
let abaAtual = 'conversa';
let configApp = {};         // /api/config (atividades, avaliacao.referencias, ...)
let pastaAtual = null;
let assinaturaConversa = '';
let ultimaSaidaCard = '';
let dialogoAbertoUmaVez = false;
const cache = {}; // nome do arquivo -> { versao, texto }

// Roteiro da barra lateral. Cada etapa e marcada pelo que de fato aconteceu neste card;
// "status" e a linha curta embaixo do nome (numeros de estado.resumo, vindos do servidor).
// Etapa "encadeada" feita marca as anteriores (o plano existe => commits, avaliacao e
// banco ja passaram). "Seus testes" e opcional: mostra o progresso, mas nao vira a etapa
// atual nem segura o Simular.
const ETAPAS = [
  // os commits so contam como confirmados depois que o dev respondeu ao agente
  { nome: 'Commits', aba: 'commits', encadeada: true,
    feita: (a, e) => !!a['contexto.md'] && (e.conversa || []).filter((m) => m.quem === 'dev').length >= 2,
    status: (a, e, r) => r.commits ? plural(r.commits, 'commit', 'commits') : '' },
  { nome: 'Avaliação', aba: 'avaliacao', encadeada: true, feita: (a) => !!a['avaliacao.md'],
    status: (a, e, r) => !r.criterios ? '' : [plural(r.criterios, 'critério', 'critérios'),
      r.pendentes ? plural(r.pendentes, 'pendente', 'pendentes') : '', r.aTestar ? r.aTestar + ' a testar' : ''].filter(Boolean).join(' · ') },
  { nome: 'Banco', aba: 'banco', encadeada: true, feita: (a) => !!a['banco.md'], status: (a, e, r) => r.banco || '' },
  { nome: 'Plano de teste', aba: 'plano', encadeada: true, feita: (a) => !!a['plano.md'],
    status: (a, e, r) => r.cenarios ? plural(r.cenarios, 'cenário', 'cenários') : '' },
  { nome: 'Seus testes', aba: 'plano', opcional: true, feita: (a) => !!a['execucao.md'],
    status: (a, e, r) => !r.cenarios ? 'opcional' : [r.testesFeitos + ' de ' + r.cenarios + ' feitos',
      r.evidencias ? plural(r.evidencias, 'evidência', 'evidências') : '', a['execucao.md'] ? 'enviados' : ''].filter(Boolean).join(' · ') },
  ETAPA_SIMULAR(),
  ETAPA_PUBLICAR(),
];

// Avaliacao tecnica (antes do desenvolvimento): sem commits, banco nem plano.
const ETAPAS_AVALIACAO = [
  { nome: 'Card e referência', aba: 'criterios', encadeada: true, feita: (a) => !!a['contexto.md'],
    status: (a, e, r) => r.referencia ? 'código de ' + r.referencia : '' },
  // o escopo so conta como confirmado depois que o dev respondeu ao agente
  { nome: 'Escopo', aba: 'conversa', encadeada: true,
    feita: (a, e) => !!a['contexto.md'] && (e.conversa || []).filter((m) => m.quem === 'dev').length >= 2,
    status: (a, e, r) => [r.criterios ? plural(r.criterios, 'critério', 'critérios') : '',
      r.paginasWiki ? plural(r.paginasWiki, 'página da wiki', 'páginas da wiki') : ''].filter(Boolean).join(' · ') },
  { nome: 'Impacto e riscos', aba: 'avaliacao', encadeada: true, feita: (a) => !!a['avaliacao-tecnica.md'], status: () => '' },
  { nome: 'Estimativa', aba: 'avaliacao', encadeada: true, feita: (a, e) => !!(e.resumo && e.resumo.pontosAprovados),
    status: (a, e, r) => r.pontos ? plural(r.pontos, 'ponto', 'pontos') + (r.pontosAprovados ? ' aprovados' : ' sugeridos') : '' },
  ETAPA_SIMULAR(),
  ETAPA_PUBLICAR(),
];

function ETAPA_SIMULAR() {
  return { nome: 'Simular', aba: 'publicar', feita: (a, e) => simulacaoValida(a, e),
    status: (a, e) => {
      const u = e.ultimaSimulacao;
      if (!a[arquivoDecisao()]) return a[emAvaliacao() ? 'avaliacao-tecnica.md' : 'plano.md'] ? 'aguardando a decisão do agente' : '';
      if (!u) return 'pronto para simular';
      if (u.codigo !== 0) return 'terminou com erro';
      return simulacaoValida(a, e) ? 'ok às ' + hora(u.quando) : 'desatualizado: simule de novo';
    } };
}

// publicacao deste fluxo: um historico de antes (mesmo card publicado outra vez) nao conta
function ETAPA_PUBLICAR() {
  return { nome: 'Publicar', aba: 'publicar', feita: (a, e) => !!a['historico'] && (!e.inicio || a['historico'] > e.inicio),
    status: (a, e) => (a['historico'] && (!e.inicio || a['historico'] > e.inicio)) ? 'publicado ' + dataHora(a['historico']) : '' };
}

function emAvaliacao() { return !!(typeof estado !== 'undefined' && estado && estado.modo === 'avaliacao'); }
function arquivoDecisao() { return emAvaliacao() ? 'decisao-avaliacao.json' : 'decisao.json'; }
// o que, mudando depois do Simular, obriga a simular de novo (igual ao servidor)
function invalidamSimular() {
  return emAvaliacao() ? ['avaliacao-tecnica.md', 'decisao-avaliacao.json'] : ['decisao.json', 'plano.md', 'execucao.md', 'banco.sql', 'evidencias'];
}

// Simular sem erro e ainda valido: nada do que entra no card mudou depois dele.
function simulacaoValida(a, e) {
  const u = e.ultimaSimulacao;
  if (!u || u.codigo !== 0) return false;
  return !invalidamSimular().some((n) => (a[n] || '') > u.quando);
}

// ---------------- servidor ----------------

async function api(caminho, corpo) {
  const opcoes = corpo === undefined ? {} : {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Token': TOKEN },
    body: JSON.stringify(corpo),
  };
  const r = await fetch(caminho, opcoes);
  let dados = {};
  try { dados = await r.json(); } catch (e) { /* resposta sem corpo */ }
  if (!r.ok) throw new Error(dados.erro || ('HTTP ' + r.status));
  return dados;
}

function avisar(texto) {
  const el = $('#aviso');
  el.textContent = texto;
  el.hidden = false;
  clearTimeout(avisar.t);
  avisar.t = setTimeout(() => { el.hidden = true; }, 7000);
}

async function carregarArquivo(nome) {
  const versao = estado && estado.arquivos ? estado.arquivos[nome] : null;
  if (!versao) return '';
  const c = cache[nome];
  if (c && c.versao === versao) return c.texto;
  const r = await api('/api/arquivo?nome=' + encodeURIComponent(nome));
  cache[nome] = { versao, texto: r.texto || '' };
  return cache[nome].texto;
}

// ---------------- markdown ----------------

function esc(s) {
  return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

let mdSemSelos = false; // na previa do comentario, situacao fica como texto (igual ao GitLab)

function inline(s) {
  // codigo sai antes e volta no fim: "_" e "**" dentro de `...` nao viram italico/negrito
  const codigos = [];
  let t = esc(s).replace(/`([^`]+)`/g, (m, c) => { codigos.push(c); return '§§' + (codigos.length - 1) + '§§'; });
  // evidencia na previa do comentario: ![nome](evidencia:cenario-N/arquivo) mostra o arquivo local
  t = t.replace(/!\[([^\]]*)\]\(evidencia:(cenario-\d+)\/([A-Za-z0-9._-]+)\)/g, (m, alt, chave, nome) => {
    const url = urlEvidencia(chave, nome);
    return /\.(mp4|webm|mov)$/i.test(nome)
      ? '<video class="evid-previa" src="' + url + '" controls preload="metadata"></video>'
      : '<img class="evid-previa" src="' + url + '" alt="' + alt + '">';
  });
  t = t.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  t = t.replace(/(^|[\s(])_([^_\n]+)_(?=[\s).,;:!?]|$)/g, '$1<em>$2</em>');
  t = t.replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
  if (!mdSemSelos) {
    t = t.replace(/\b(atendido|parcial|nao_atendido|nao_encontrado|verificar_no_teste)\b/g, (m) => {
      const classe = m === 'atendido' ? 'atendido' : (m === 'verificar_no_teste' ? 'teste' : 'pendente');
      return '<span class="situacao ' + classe + '">' + m.replace(/_/g, ' ') + '</span>';
    });
  }
  return t.replace(/§§(\d+)§§/g, (m, i) => '<code>' + codigos[Number(i)] + '</code>');
}

function celulas(linha) {
  return linha.trim().replace(/^\|/, '').replace(/\|$/, '').split(/(?<!\\)\|/).map((c) => c.trim().replace(/\\\|/g, '|'));
}

function md(texto) {
  const linhas = String(texto || '').replace(/\r/g, '').split('\n');
  const ehBloco = (l) => /^```/.test(l) || /^#{1,6}\s/.test(l) || /^\s*([-*+]|\d+[.)])\s+/.test(l) || /^\s*>/.test(l) || /^\s*\|.*\|\s*$/.test(l) || /^\s*(---|\*\*\*)\s*$/.test(l);
  let html = '';
  let i = 0;
  while (i < linhas.length) {
    const l = linhas[i];
    let m;
    if (/^```/.test(l)) {
      const bloco = [];
      i++;
      while (i < linhas.length && !/^```/.test(linhas[i])) bloco.push(linhas[i++]);
      i++;
      html += '<pre><code>' + esc(bloco.join('\n')) + '</code></pre>';
    } else if ((m = l.match(/^(#{1,6})\s+(.*)$/))) {
      const n = Math.min(m[1].length, 4);
      html += '<h' + n + '>' + inline(m[2]) + '</h' + n + '>';
      i++;
    } else if (/^\s*\|.*\|\s*$/.test(l) && i + 1 < linhas.length && /^\s*\|?\s*:?-{2,}/.test(linhas[i + 1])) {
      const cab = celulas(l);
      i += 2;
      html += '<table><thead><tr>' + cab.map((c) => '<th>' + inline(c) + '</th>').join('') + '</tr></thead><tbody>';
      while (i < linhas.length && /^\s*\|.*\|\s*$/.test(linhas[i])) {
        html += '<tr>' + celulas(linhas[i]).map((c) => '<td>' + inline(c) + '</td>').join('') + '</tr>';
        i++;
      }
      html += '</tbody></table>';
    } else if (/^\s*([-*+]|\d+[.)])\s+/.test(l)) {
      const ordenada = /^\s*\d+[.)]/.test(l);
      html += ordenada ? '<ol>' : '<ul>';
      while (i < linhas.length && linhas[i].trim() && (/^\s*([-*+]|\d+[.)])\s+/.test(linhas[i]) || /^\s{2,}\S/.test(linhas[i]))) {
        const item = linhas[i].match(/^(\s*)([-*+]|\d+[.)])\s+(.*)$/);
        if (item) {
          const nivel = Math.floor(item[1].length / 2);
          html += '<li style="margin-left:' + (nivel * 1.2) + 'em">' + inline(item[3]);
          i++;
          while (i < linhas.length && /^\s{2,}\S/.test(linhas[i]) && !/^\s*([-*+]|\d+[.)])\s+/.test(linhas[i])) {
            html += ' ' + inline(linhas[i].trim());
            i++;
          }
          html += '</li>';
        } else {
          i++;
        }
      }
      html += ordenada ? '</ol>' : '</ul>';
    } else if (/^\s*>/.test(l)) {
      const bloco = [];
      while (i < linhas.length && /^\s*>/.test(linhas[i])) bloco.push(linhas[i++].replace(/^\s*>\s?/, ''));
      html += '<blockquote>' + md(bloco.join('\n')) + '</blockquote>';
    } else if (/^\s*(---|\*\*\*)\s*$/.test(l)) {
      html += '<hr>';
      i++;
    } else if (!l.trim()) {
      i++;
    } else {
      const par = [];
      while (i < linhas.length && linhas[i].trim() && !ehBloco(linhas[i])) par.push(linhas[i++]);
      if (par.length === 0) par.push(linhas[i++]);
      html += '<p>' + par.map(inline).join('<br>') + '</p>';
    }
  }
  return html;
}

// ---------------- perguntas do agente ----------------
// O agente termina o turno que espera resposta com
//   <!-- card-sigcon:perguntas [ {"pergunta", "opcoes": [...], "multipla"} ] -->
// (steering fluxo-card-sigcon.md). A pagina tira o bloco do texto, destaca as perguntas
// na mensagem e monta o painel de resposta acima da caixa.
const RX_BLOCO_PERGUNTAS = /<!--\s*card-sigcon:perguntas\s*([\s\S]*?)-->/g;

function perguntasDoBloco(texto) {
  let lista = [];
  String(texto || '').replace(RX_BLOCO_PERGUNTAS, (m, json) => {
    try { const l = JSON.parse(json); if (Array.isArray(l)) lista = lista.concat(l); } catch (e) { /* bloco mal formado: ignora */ }
    return m;
  });
  return lista.filter((p) => p && p.pergunta).slice(0, 6).map((p) => ({
    pergunta: String(p.pergunta),
    opcoes: (Array.isArray(p.opcoes) ? p.opcoes : []).map(String).filter(Boolean).slice(0, 6),
    multipla: !!p.multipla,
  }));
}

// tambem tira o bloco ainda incompleto (log ao vivo, antes do "-->")
function semBlocoPerguntas(texto) {
  return String(texto || '').replace(RX_BLOCO_PERGUNTAS, '').replace(/<!--\s*card-sigcon:perguntas[\s\S]*$/, '');
}

// Sem o bloco (o agente esqueceu): as frases terminadas em "?" do fim da mensagem.
function perguntasSoltas(texto) {
  const linhas = semBlocoPerguntas(texto).split('\n').filter((l) => !/^\[(tool|denied)\]/.test(l));
  const achadas = [];
  for (const l of linhas.slice(-40)) {
    const limpa = l.replace(/^\s*([-*+>]|\d+[.)])\s+/, '').replace(/\*\*|__|`/g, '').trim();
    if (limpa.length > 8 && limpa.length < 300 && /\?\s*$/.test(limpa)) achadas.push({ pergunta: limpa, opcoes: [], multipla: false });
  }
  return achadas.slice(-5);
}

// Saida do Kiro: as linhas "[tool] ..." viram um grupo recolhivel de acoes; o resto e
// markdown do agente; o bloco de perguntas vira um quadro em destaque no fim.
function mensagemAgente(texto, vivo) {
  const perguntas = vivo ? [] : perguntasDoBloco(texto);
  const linhas = semBlocoPerguntas(texto).replace(/\r/g, '').split('\n');
  let html = '';
  let corpo = [];
  let acoes = [];
  const fecharCorpo = () => {
    if (corpo.join('').trim()) html += '<div class="md">' + md(corpo.join('\n')) + '</div>';
    corpo = [];
  };
  const fecharAcoes = (ultimo) => {
    if (!acoes.length) return;
    const falhas = acoes.filter((a) => a.falhou).length;
    let resumo = '⚙ ' + acoes.length + (acoes.length === 1 ? ' ação' : ' ações') + ' do agente';
    if (falhas) resumo += ' · ' + falhas + ' bloqueada' + (falhas === 1 ? '' : 's');
    if (vivo && ultimo) resumo += ' · agora: ' + acoes[acoes.length - 1].texto.slice(0, 90);
    html += '<details class="atividades"><summary>' + esc(resumo) + '</summary><div class="lista">' +
      acoes.map((a) => '<div class="ferramenta' + (a.falhou ? ' falhou' : '') + '" title="' + esc(a.texto) + '">' + esc(a.texto) + '</div>').join('') +
      '</div></details>';
    acoes = [];
  };
  for (const l of linhas) {
    if (/^\[denied\]/.test(l)) {
      fecharCorpo();
      acoes.push({ texto: 'comando fora da lista liberada do agente (o Kiro não pergunta neste modo)', falhou: true });
      continue;
    }
    const m = l.match(/^\[tool\]\s*(.*)$/);
    if (!m) {
      if (l.trim()) fecharAcoes(false);
      corpo.push(l);
      continue;
    }
    fecharCorpo();
    const t = m[1];
    if (/^status:\s*Completed/i.test(t)) continue;
    if (/^status:/i.test(t)) {
      if (acoes.length) acoes[acoes.length - 1].falhou = true;
      continue;
    }
    acoes.push({ texto: t.replace(/^Running:\s*/, ''), falhou: false });
  }
  fecharCorpo();
  fecharAcoes(true);
  if (perguntas.length) {
    html += '<div class="perguntas-msg"><div class="perguntas-msg-titulo">Perguntas para você</div><ol>' +
      perguntas.map((p) => '<li>' + inline(p.pergunta) +
        (p.opcoes.length ? '<div class="perguntas-msg-opcoes">' + p.opcoes.map((o) => '<span>' + esc(o) + '</span>').join('') + '</div>' : '') + '</li>').join('') +
      '</ol></div>';
  }
  return html;
}

function secoes(texto, prefixos, incluirCabecalho) {
  const partes = String(texto || '').split(/\n(?=## )/);
  const escolhidas = partes.filter((p) => prefixos.some((x) => p.startsWith('## ' + x)));
  if (incluirCabecalho && partes.length && !partes[0].startsWith('## ')) escolhidas.unshift(partes[0]);
  return escolhidas.join('\n\n');
}

// ---------------- renderizacao ----------------

function hora(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  return isNaN(d) ? iso : d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
}

function renderTopo() {
  const el = $('#status');
  const t = estado.tarefa;
  el.className = 'status';
  if (t && t.rodando) {
    const seg = Math.max(0, Math.round((Date.now() - new Date(t.inicio).getTime()) / 1000));
    const nome = { kiro: 'Kiro trabalhando', simular: 'Simulando', publicar: 'Publicando no GitLab' }[t.tipo] || 'Rodando';
    el.textContent = nome + ' · ' + (seg >= 60 ? Math.floor(seg / 60) + ' min ' + (seg % 60) + ' s' : seg + ' s');
    el.classList.add('ocupado');
  } else {
    el.textContent = estado.card ? 'Pronto' : 'Sem card';
  }
  const temCard = !!estado.card;
  $('#topo-modo').hidden = !(temCard && emAvaliacao());
  $('#card-atual').hidden = !temCard;
  $('#bloco-card').hidden = !temCard;
  if (temCard) {
    $('#topo-iid').textContent = '#' + estado.iid;
    $('#topo-titulo').textContent = estado.titulo || '';
    $('#topo-link').href = /^https?:/.test(estado.card) ? estado.card : '#';
    $('#topo-link').title = estado.titulo || estado.card;
    // quebra a linha depois das barras, nao no meio da palavra
    $('#resumo-branch').innerHTML = esc(estado.branch).replace(/\//g, '/<wbr>');
    $('#resumo-base').innerHTML = esc(estado.base).replace(/\//g, '/<wbr>');
  }
  renderCreditos(temCard);
}

// ---------------- creditos do Kiro ----------------

function fmtCreditos(n) {
  const v = Number(n) || 0;
  return v.toLocaleString('pt-BR', { minimumFractionDigits: 1, maximumFractionDigits: v < 1 ? 2 : 1 }) + (v === 1 ? ' crédito' : ' créditos');
}

function renderCreditos(temCard) {
  const cr = estado.creditos || {};
  const topo = $('#topo-creditos');
  topo.hidden = !(temCard && cr.cardTurnos);
  if (!topo.hidden) {
    topo.textContent = fmtCreditos(cr.card);
    topo.title = 'Créditos do Kiro gastos neste card: ' + cr.cardTurnos + (cr.cardTurnos === 1 ? ' resposta' : ' respostas') + ', somando todas as conversas dele';
  }
  const mes = new Date().toLocaleString('pt-BR', { month: 'long' });
  $('#creditos-mes').textContent = cr.mesTurnos
    ? fmtCreditos(cr.mes) + ' em ' + mes + ' · ' + cr.mesTurnos + (cr.mesTurnos === 1 ? ' resposta' : ' respostas')
    : 'Nada gasto em ' + mes + ' pela página.';
}

function renderEtapas() {
  const a = estado.arquivos || {};
  const ol = $('#etapas');
  ol.innerHTML = '';
  const r = estado.resumo || {};
  const lista = emAvaliacao() ? ETAPAS_AVALIACAO : ETAPAS;
  let atualMarcada = false;
  const proprias = lista.map((et) => !!estado.card && et.feita(a, estado));
  lista.forEach((et, n) => {
    // encadeada: feita se ela ou qualquer etapa obrigatoria depois dela foi feita
    const feita = proprias[n] || (et.encadeada && lista.some((x, j) => j > n && !x.opcional && proprias[j]));
    const li = document.createElement('li');
    const classes = [];
    if (et.opcional) classes.push('opcional');
    if (!estado.card) classes.push('inativa');
    else if (feita) classes.push('feita');
    else if (!atualMarcada && !et.opcional) { classes.push('atual'); atualMarcada = true; }
    li.className = classes.join(' ');
    if (et.nome === 'Simular' && !feita && estado.ultimaSimulacao && estado.ultimaSimulacao.codigo === 0) {
      li.title = emAvaliacao() ? 'A avaliação ou a decisão mudaram depois do último Simular: simule de novo.'
        : 'Plano, testes, evidências, SQL do banco ou decisão mudaram depois do último Simular: simule de novo.';
    }
    const status = estado.card ? et.status(a, estado, r) : '';
    const b = document.createElement('button');
    b.type = 'button';
    b.disabled = !estado.card;
    b.innerHTML = '<span class="marcador">' + (feita ? '✓' : (n + 1)) + '</span><span class="etapa-texto"><span>' + esc(et.nome) + '</span>' +
      (status ? '<small class="etapa-status">' + esc(status) + '</small>' : '') + '</span>';
    b.addEventListener('click', () => abrirAba(et.aba));
    li.appendChild(b);
    ol.appendChild(li);
  });
  const temConteudo = { commits: a['contexto.md'], criterios: a['contexto.md'], avaliacao: a[emAvaliacao() ? 'avaliacao-tecnica.md' : 'avaliacao.md'], banco: a['banco.md'] || a['contexto.md'], plano: a['plano.md'] };
  // avaliacao tecnica nao tem commits, banco nem plano
  const escondidas = emAvaliacao() ? ['commits', 'banco', 'plano'] : [];
  $$('#abas button').forEach((b) => {
    b.hidden = escondidas.includes(b.dataset.aba);
    if (b.hidden && abaAtual === b.dataset.aba) abrirAba('conversa');
    const p = b.querySelector('.ponto');
    if (temConteudo[b.dataset.aba] && !p) b.insertAdjacentHTML('beforeend', '<span class="ponto"></span>');
    if (!temConteudo[b.dataset.aba] && p) p.remove();
  });
  // contador de propostas pendentes na aba Aprendizado
  const abaAp = document.querySelector('#abas button[data-aba="aprendizado"]');
  let cont = abaAp.querySelector('.contador');
  if (estado.propostas > 0) {
    if (!cont) { abaAp.insertAdjacentHTML('beforeend', '<span class="contador"></span>'); cont = abaAp.querySelector('.contador'); }
    cont.textContent = estado.propostas;
    cont.title = estado.propostas + (estado.propostas === 1 ? ' proposta pendente' : ' propostas pendentes');
  } else if (cont) {
    cont.remove();
  }
  if (abaAtual === 'aprendizado' && estado.propostas !== totalPropostasVisto) carregarPropostas();
}

function renderConversa() {
  const conv = estado.conversa || [];
  const t = estado.tarefa;
  const rodandoKiro = !!(t && t.rodando && t.tipo === 'kiro');
  const rol = $('#rolagem-conversa');
  const pertoDoFim = rol.scrollHeight - rol.scrollTop - rol.clientHeight < 140;
  let mudou = false;

  $('#vazio').hidden = conv.length > 0;
  const assinatura = conv.length + '|' + (conv.length ? conv[conv.length - 1].quando : '');
  if (assinatura !== assinaturaConversa) {
    const novaDoDev = conv.length && conv[conv.length - 1].quem === 'dev';
    assinaturaConversa = assinatura;
    $('#conversa').innerHTML = conv.map((m) => {
      if (m.quem === 'dev') {
        return '<div class="msg dev"><div class="msg-cabecalho"><span class="autor">Você</span><span>' + hora(m.quando) + '</span></div>' + esc(m.texto) + '</div>';
      }
      const erro = m.codigo && m.codigo !== 0;
      return '<div class="msg agente' + (erro ? ' erro' : '') + '"><div class="msg-cabecalho"><span class="autor">Kiro</span><span>' + hora(m.quando) + '</span>' +
        (typeof m.creditos === 'number' ? '<span title="Créditos do Kiro gastos nesta resposta">· ' + fmtCreditos(m.creditos) + '</span>' : '') +
        (erro ? '<span>· terminou com erro (' + m.codigo + ')</span>' : '') + '</div>' + mensagemAgente(m.texto, false) + '</div>';
    }).join('');
    mudou = true;
    if (novaDoDev) rol.scrollTop = rol.scrollHeight;
  }
  $('#trabalhando').hidden = !rodandoKiro;
  if (rodandoKiro) {
    const vivo = $('#log-vivo');
    const novo = mensagemAgente(estado.log, true) || '<p class="dica">aguardando o Kiro…</p>';
    if (vivo.dataset.html !== novo) {
      // preserva os grupos que o dev abriu
      const abertos = $$('#log-vivo details').map((d) => d.open);
      vivo.innerHTML = novo;
      vivo.dataset.html = novo;
      $$('#log-vivo details').forEach((d, i) => { if (abertos[i]) d.open = true; });
      mudou = true;
    }
  }
  if (mudou && pertoDoFim) rol.scrollTop = rol.scrollHeight;

  const podeResponder = !!estado.card && estado.temSessao && !(t && t.rodando);
  $('#form-resposta').hidden = !estado.card;
  $$('#form-resposta button, #form-resposta textarea, #form-resposta input').forEach((el) => { el.disabled = !podeResponder; });
  renderPerguntas(podeResponder);
}

// Painel acima da caixa com as perguntas da ultima mensagem do agente (opcoes como botoes
// e um campo para outra resposta). So e refeito quando chega mensagem nova, para nao
// apagar o que o dev ja marcou.
let chavePerguntas = '';
let perguntasAtuais = [];

function renderPerguntas(podeResponder) {
  const conv = estado.conversa || [];
  const ult = conv[conv.length - 1];
  const ativo = !!(podeResponder && ult && ult.quem === 'agente' && !(ult.codigo && ult.codigo !== 0));
  const chave = ativo ? conv.length + '|' + ult.quando : '';
  if (chave === chavePerguntas) return;
  chavePerguntas = chave;
  let lista = [];
  let soltas = false;
  if (ativo) {
    lista = perguntasDoBloco(ult.texto);
    if (!lista.length) { lista = perguntasSoltas(ult.texto); soltas = lista.length > 0; }
  }
  perguntasAtuais = lista;
  const painel = $('#painel-perguntas');
  painel.hidden = !lista.length;
  $('#atalhos').hidden = lista.length > 0;
  caixaResposta.placeholder = lista.length ? 'Algo a mais para o agente (opcional)…  (Ctrl+Enter envia)' : 'Responda ao agente…  (Ctrl+Enter envia)';
  if (!lista.length) { painel.innerHTML = ''; return; }
  painel.innerHTML = '<div class="perguntas-topo"><strong>O agente está esperando a sua resposta</strong>' +
    (soltas ? '<span class="dica">perguntas achadas no fim da mensagem</span>' : '') + '</div>' +
    lista.map((p, i) => '<div class="pergunta" data-i="' + i + '" data-multipla="' + (p.multipla ? '1' : '') + '">' +
      '<div class="pergunta-texto"><span class="num">' + (i + 1) + '</span><span>' + inline(p.pergunta) +
      (p.multipla ? ' <span class="dica">(pode marcar mais de uma)</span>' : '') + '</span></div>' +
      (p.opcoes.length ? '<div class="opcoes">' + p.opcoes.map((o) => '<button type="button" class="opcao" aria-pressed="false">' + esc(o) + '</button>').join('') + '</div>' : '') +
      '<input type="text" class="pergunta-outra" placeholder="' + (p.opcoes.length ? 'Outra resposta ou complemento…' : 'Sua resposta…') + '"></div>').join('') +
    '<div class="perguntas-acoes"><button type="button" class="botao primario" id="btn-responder-perguntas">Enviar respostas</button></div>';
}

function temRespostaNoPainel() {
  return $$('#painel-perguntas .opcao[aria-pressed="true"]').length > 0 || $$('#painel-perguntas .pergunta-outra').some((i) => i.value.trim());
}

// "1. Pergunta\n   → resposta" para cada pergunta, mais o que o dev escreveu na caixa.
async function enviarRespostasPerguntas() {
  const extra = caixaResposta.value.trim();
  if (!temRespostaNoPainel() && !extra) { avisar('Marque uma opção ou escreva a resposta.'); return; }
  const partes = $$('#painel-perguntas .pergunta').map((el) => {
    const i = Number(el.dataset.i);
    const marcadas = $$('.opcao[aria-pressed="true"]', el).map((b) => b.textContent);
    const outra = el.querySelector('.pergunta-outra').value.trim();
    const resposta = [marcadas.join('; '), outra].filter(Boolean).join(' — ') || '(sem resposta)';
    return (perguntasAtuais.length > 1 ? (i + 1) + '. ' : '') + perguntasAtuais[i].pergunta + '\n   → ' + resposta;
  });
  const texto = partes.join('\n') + (extra ? '\n\n' + extra : '');
  try {
    await api('/api/responder', { texto });
    caixaResposta.value = '';
    ajustarAltura();
    await atualizar();
  } catch (e) { avisar(e.message); }
}

$('#painel-perguntas').addEventListener('click', (ev) => {
  const op = ev.target.closest('.opcao');
  if (op) {
    const pergunta = op.closest('.pergunta');
    const marcar = op.getAttribute('aria-pressed') !== 'true';
    if (!pergunta.dataset.multipla) $$('.opcao', pergunta).forEach((b) => b.setAttribute('aria-pressed', 'false'));
    op.setAttribute('aria-pressed', marcar ? 'true' : 'false');
    return;
  }
  if (ev.target.closest('#btn-responder-perguntas')) enviarRespostasPerguntas();
});
$('#painel-perguntas').addEventListener('keydown', (ev) => {
  if (ev.key === 'Enter' && ev.target.classList.contains('pergunta-outra')) { ev.preventDefault(); enviarRespostasPerguntas(); }
});

// mesma chave do servidor (Chave-Opcoes): coluna|atividade|semFilho|novoFilho|pontos
function chaveOpcoes(o) {
  const b = (v) => (v ? 'True' : 'False');
  return (o.coluna || '') + '|' + (o.atividade || '') + '|' + b(o.semFilho) + '|' + b(o.novoFilho) + '|' + (o.pontos || '');
}

function opcoesPublicar() {
  const f = $('#form-publicar');
  const av = emAvaliacao();
  // na avaliacao o filho e sempre "Avaliação Técnica" e os pontos vem da lista; no fechamento, o contrario
  return { coluna: f.coluna.value, atividade: av ? '' : f.atividade.value, semFilho: f.semFilho.checked, novoFilho: f.novoFilho.checked, pontos: av ? f.pontos.value : '' };
}

// Colunas do quadro do card, lidas do GitLab ao abrir a aba Publicar (uma vez por card).
let colunasDoCard = '';

async function carregarColunas() {
  if (!estado || !estado.card || colunasDoCard === estado.pasta) return;
  const sel = $('#sel-coluna');
  const dica = $('#dica-coluna');
  dica.textContent = 'Lendo as colunas do quadro no GitLab…';
  try {
    const r = await api('/api/colunas');
    colunasDoCard = estado.pasta;
    const escolhida = sel.value;
    sel.innerHTML = '<option value="">Não mover</option>' + (r.colunas || []).map((c) => {
      const atual = c === r.atual;
      return '<option value="' + esc(c) + '"' + (atual ? ' disabled' : '') + '>' + esc(c) + (atual ? ' (coluna atual)' : '') + '</option>';
    }).join('');
    if ([...sel.options].some((o) => o.value === escolhida && !o.disabled)) sel.value = escolhida;
    dica.textContent = r.quadro ? 'Quadro "' + r.quadro + '"' + (r.atual ? ', hoje em "' + r.atual + '".' : '.') : 'Não achei o quadro do card.';
    if (emAvaliacao()) {
      // avaliacao: sugere a coluna seguinte (config) e lista a escala de pontos do projeto
      const destino = configApp.avaliacao && configApp.avaliacao.colunaDestino;
      const opt = [...sel.options].find((o) => o.value && !o.disabled && semAcento(o.value) === semAcento(destino || ''));
      if (!sel.value && opt) sel.value = opt.value;
      const sp = $('#sel-pontos');
      const sugeridos = (estado.resumo || {}).pontos;
      sp.innerHTML = '<option value="">Os da decisão' + (sugeridos ? ' (' + plural(sugeridos, 'ponto', 'pontos') + ')' : '') + '</option>' +
        (r.pontos || []).map((p) => '<option value="' + p.pontos + '">' + esc(p.nome) + '</option>').join('');
      $('#dica-pontos').textContent = 'Hoje o card está com: ' + (r.pontosHoje || 'sem etiqueta de pontos') + '. O Publicar troca pela etiqueta escolhida e o filho "Avaliação Técnica" vai com ela.';
    }
  } catch (e) {
    dica.textContent = 'Não consegui ler as colunas: ' + e.message;
  }
  renderPublicar();
}

function renderPublicar() {
  const a = estado.arquivos || {};
  const t = estado.tarefa;
  const ocupado = !!(t && t.rodando);
  const u = estado.ultimaSimulacao;
  const av = emAvaliacao();
  const decisao = arquivoDecisao();
  const texto = av ? 'nota-avaliacao.md' : 'comentario-plano.md';
  $('#campo-pontos').hidden = !av;
  $('#dica-pontos').hidden = !av;
  $('#campo-atividade').hidden = av;
  const edicoes = estado.edicoes || {};
  const temEdicao = Object.keys(edicoes).length > 0;
  $('#btn-previa').textContent = (av ? 'Pré-visualizar nota interna' : 'Pré-visualizar comentário') + (temEdicao ? ' (editado por você)' : '');
  let motivo = '';
  if (!estado.card) motivo = 'Comece um card.';
  else if (!a[decisao]) motivo = 'O agente ainda não gravou a decisão (' + decisao + ').';
  else if (!u || u.codigo !== 0) motivo = 'Rode o Simular sem erro antes de publicar.';
  else if (u.opcoes !== chaveOpcoes(opcoesPublicar())) motivo = 'As opções mudaram desde o último Simular: simule de novo.';
  else if (!simulacaoValida(a, estado)) motivo = (av ? 'A avaliação ou a decisão mudaram' : 'O plano, a execução dos testes ou a decisão mudaram') + ' depois do último Simular: simule de novo.';
  else if (Object.keys(edicoes).some((n) => edicoes[n].desatualizado)) motivo = 'O agente gerou outro texto depois da sua edição: revise na pré-visualização (salve de novo ou volte ao texto gerado).';
  $('#btn-simular').disabled = ocupado || !estado.card || !a[decisao];
  $('#btn-previa').disabled = !a[texto];
  $('#btn-previa').title = a[texto] ? 'Mostra o texto como vai ficar no card' : 'Rode o Simular para gerar o texto';
  $('#btn-publicar').disabled = ocupado || !!motivo;
  $('#motivo-publicar').textContent = motivo;
  if (t && (t.tipo === 'simular' || t.tipo === 'publicar')) {
    ultimaSaidaCard = (t.rodando ? '(rodando…)\n' : '') + (estado.log || '');
  }
  $('#saida-card').textContent = ultimaSaidaCard || 'Nada ainda.';
}

let chaveAbaRenderizada = '';

async function renderAbaArquivo() {
  const a = estado.arquivos || {};
  // So redesenha quando a aba ou a versao dos arquivos muda (o estado chega a cada 2 s).
  const chave = abaAtual + '|' + estado.pasta + '|' + ['contexto.md', 'avaliacao.md', 'banco.md', 'plano.md', 'execucao.md', 'comentario-plano.md', 'avaliacao-tecnica.md'].map((n) => a[n] || '').join('|');
  if (chave === chaveAbaRenderizada) return;
  chaveAbaRenderizada = chave;
  try {
    if (abaAtual === 'commits') {
      const ctx = await carregarArquivo('contexto.md');
      $('#md-commits').innerHTML = ctx ? md(secoes(ctx, ['Commits', 'Alertas'], true)) : vazio('Os commits aparecem aqui depois do coletar.');
    } else if (abaAtual === 'criterios') {
      const ctx = await carregarArquivo('contexto.md');
      $('#md-criterios').innerHTML = ctx
        ? '<p class="nota-topo">Lista extraída da HU pelo script. A que vale é a que você confirmar na conversa.</p>' + md(secoes(ctx, ['Criterios']))
        : vazio('Os critérios aparecem aqui depois do coletar.');
    } else if (abaAtual === 'avaliacao' && emAvaliacao()) {
      const t = await carregarArquivo('avaliacao-tecnica.md');
      $('#md-avaliacao').innerHTML = t
        ? '<p class="nota-topo">Vai como nota interna no card filho "Avaliação Técnica" (só a equipe vê).</p>' + md(t)
        : vazio('O agente grava a avaliação técnica depois que você confirma o escopo e aprova os pontos.');
    } else if (abaAtual === 'avaliacao') {
      const t = await carregarArquivo('avaliacao.md');
      $('#md-avaliacao').innerHTML = t ? md(t) : vazio('O agente grava a avaliação depois que você confirma os critérios.');
    } else if (abaAtual === 'banco') {
      if (a['banco.md']) {
        $('#md-banco').innerHTML = md(await carregarArquivo('banco.md'));
      } else {
        const ctx = await carregarArquivo('contexto.md');
        $('#md-banco').innerHTML = ctx
          ? '<p class="nota-topo">Camada 1 (script). O julgamento do agente e as suas respostas aparecem aqui quando ele gravar o banco.md.</p>' + md(secoes(ctx, ['Banco']))
          : vazio('A checagem de banco aparece aqui depois do coletar.');
      }
    } else if (abaAtual === 'plano') {
      const t = await carregarArquivo('plano.md');
      await salvarTestesPendentes();
      testes = {};
      if (t) {
        const r = await api('/api/arquivo?nome=execucao-testes.json');
        try { testes = (JSON.parse(r.texto || '{}').cenarios) || {}; } catch (e) { testes = {}; }
        await carregarEvidencias();
      }
      let html = t ? renderPlano(t, await carregarArquivo('execucao.md')) : vazio('O agente grava o plano depois da avaliação e do banco.');
      if (a['comentario-plano.md']) {
        html += '<h2>Como vai para o card (último Simular)</h2><pre>' + esc(await carregarArquivo('comentario-plano.md')) + '</pre>';
      }
      $('#md-plano').innerHTML = html;
      $$('#md-plano .cen-obs').forEach(ajustarAlturaObs);
      atualizarProgressoTestes();
    }
  } catch (e) {
    chaveAbaRenderizada = '';
    avisar(e.message);
  }
}

function vazio(texto) {
  return '<p class="vazio-arquivo">' + esc(texto) + '</p>';
}

// ---------------- plano: execucao dos testes pelo dev ----------------

let testes = {};            // chave do cenario -> { titulo, feito, observacao }
const timersTeste = {};     // salvamento adiado das observacoes

// Separa o plano em blocos por titulo (##, ###, ####).
function blocosDoPlano(texto) {
  const blocos = [];
  let atual = { titulo: null, cabecalho: '', linhas: [] };
  for (const l of String(texto).replace(/\r/g, '').split('\n')) {
    const m = l.match(/^#{2,4}\s+(.*)$/);
    if (m) {
      blocos.push(atual);
      atual = { titulo: m[1].trim(), cabecalho: l, linhas: [] };
    } else {
      atual.linhas.push(l);
    }
  }
  blocos.push(atual);
  return blocos.filter((b) => b.titulo !== null || b.linhas.join('').trim());
}

// Cada "### Cenário N — ..." vira um cartão com "Feito por mim" e observação.
// A chave e o numero do cenario, por isso o agente nao renumera os cenarios.
// A secao "Execução pelo dev" (execucao.md) aparece antes do primeiro cenario, onde o
// card.ps1 tambem a coloca no comentario.
function renderPlano(texto, execucao) {
  const secaoExecucao = execucao && execucao.trim()
    ? '<section class="secao-execucao"><div class="selo-card">vai no card</div>' + md(execucao) + '</section>'
    : '';
  let execucaoPosta = false;
  const html = blocosDoPlano(texto).map((b) => {
    const corpo = (b.cabecalho ? b.cabecalho + '\n' : '') + b.linhas.join('\n');
    const m = b.titulo && b.titulo.replace(/\*/g, '').match(/^cen[aá]rio\s*(\d+)/i);
    if (!m) return md(corpo);
    let prefixo = '';
    if (!execucaoPosta) { prefixo = secaoExecucao; execucaoPosta = true; }
    const chave = 'cenario-' + m[1];
    const t = testes[chave] || {};
    const classes = 'cenario' + (t.feito ? ' feito' : '') + (t.observacao ? ' com-obs' : '') + ((evidencias[chave] || []).length ? ' com-evid' : '');
    return prefixo + '<section class="' + classes + '" data-chave="' + chave + '" data-titulo="' + esc(b.titulo) + '">' + md(corpo) +
      '<div class="cenario-rodape">' +
      '<label class="check"><input type="checkbox" class="cen-feito"' + (t.feito ? ' checked' : '') + '> Feito por mim</label>' +
      '<textarea class="cen-obs" rows="1" placeholder="Observação: o que você viu, ressalvas, problema encontrado…">' + esc(t.observacao || '') + '</textarea>' +
      '<span class="cen-salvo" aria-live="polite"></span></div>' +
      '<div class="cen-evid-area"><div class="cen-evid">' + htmlEvidencias(chave) + '</div>' +
      '<div class="cen-evid-acoes"><button type="button" class="botao discreto cen-anexar">📎 Anexar foto ou vídeo</button>' +
      '<input type="file" class="cen-arquivo" accept="image/*,video/*" multiple hidden>' +
      '<span class="dica">ou cole um print (Ctrl+V) na observação, ou arraste o arquivo para cá</span></div></div></section>';
  }).join('');
  return execucaoPosta ? html : html + secaoExecucao;
}

function cenariosNaTela() {
  return $$('#md-plano .cenario').map((s) => {
    const t = testes[s.dataset.chave] || {};
    return { chave: s.dataset.chave, titulo: s.dataset.titulo, feito: !!t.feito, observacao: (t.observacao || '').trim(), evidencias: (evidencias[s.dataset.chave] || []).length };
  });
}

// ---------------- plano: evidencias (fotos e videos por cenario) ----------------
// Ficam em out/<card>/evidencias/cenario-N/ (servidor: /api/evidencias). O Publicar envia
// ao GitLab e poe no comentario, no fim de cada cenario.

let evidencias = {};        // chave do cenario -> [{ nome, tamanho, video, quando }]
let limiteEvidMb = 0;
let extsEvid = [];

async function carregarEvidencias() {
  try {
    const r = await api('/api/evidencias');
    evidencias = r.cenarios || {};
    limiteEvidMb = r.limiteMb || 0;
    extsEvid = r.extensoes || [];
  } catch (e) { evidencias = {}; }
}

function urlEvidencia(chave, nome, quando) {
  return '/api/evidencia?chave=' + encodeURIComponent(chave) + '&nome=' + encodeURIComponent(nome) + (quando ? '&v=' + encodeURIComponent(quando) : '');
}

function tamanhoLegivel(b) {
  return b < 1048576 ? Math.max(1, Math.round(b / 1024)) + ' KB' : (b / 1048576).toFixed(1).replace('.', ',') + ' MB';
}

function htmlEvidencias(chave) {
  return (evidencias[chave] || []).map((e) => {
    const url = urlEvidencia(chave, e.nome, e.quando);
    const midia = e.video
      ? '<video src="' + url + '" preload="metadata" muted></video><span class="evid-play" aria-hidden="true">▶</span>'
      : '<img src="' + url + '" alt="' + esc(e.nome) + '" loading="lazy">';
    return '<figure class="evid" title="' + esc(e.nome) + ' · ' + tamanhoLegivel(e.tamanho) + '">' +
      '<a href="' + url + '" target="_blank" rel="noopener">' + midia + '</a>' +
      '<figcaption>' + esc(e.nome) + '</figcaption>' +
      '<button type="button" class="evid-remover" data-nome="' + esc(e.nome) + '" aria-label="Remover ' + esc(e.nome) + '">×</button></figure>';
  }).join('');
}

function atualizarEvidenciasNaTela(chave) {
  const s = document.querySelector('#md-plano .cenario[data-chave="' + chave + '"]');
  if (!s) return;
  s.querySelector('.cen-evid').innerHTML = htmlEvidencias(chave);
  s.classList.toggle('com-evid', (evidencias[chave] || []).length > 0);
}

function carimbo() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate()) + '-' + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds());
}

async function enviarEvidencias(chave, arquivos) {
  const s = document.querySelector('#md-plano .cenario[data-chave="' + chave + '"]');
  const st = s && s.querySelector('.cen-salvo');
  for (const f of arquivos) {
    // print colado chega como "image.png": ganha nome com data e hora
    let nome = f.name && !/^image\.\w+$/i.test(f.name) ? f.name : 'print-' + carimbo() + '.' + ((f.type || 'image/png').split('/')[1] || 'png').replace('jpeg', 'jpg');
    const ext = '.' + nome.split('.').pop().toLowerCase();
    if (extsEvid.length && !extsEvid.includes(ext)) { avisar(nome + ': tipo não aceito. Aceitos: ' + extsEvid.join(', ') + '.'); continue; }
    if (limiteEvidMb && f.size > limiteEvidMb * 1048576) { avisar(nome + ' tem ' + tamanhoLegivel(f.size) + ': o limite é ' + limiteEvidMb + ' MB.'); continue; }
    if (st) st.textContent = 'enviando…';
    try {
      const r = await fetch('/api/evidencias?chave=' + encodeURIComponent(chave) + '&nome=' + encodeURIComponent(nome), {
        method: 'POST', headers: { 'X-Token': TOKEN, 'Content-Type': 'application/octet-stream' }, body: f,
      });
      let d = {};
      try { d = await r.json(); } catch (e) { /* sem corpo */ }
      if (!r.ok) throw new Error(d.erro || ('HTTP ' + r.status));
    } catch (e) { avisar('Não anexou ' + nome + ': ' + e.message); }
  }
  if (st) st.textContent = '';
  await carregarEvidencias();
  atualizarEvidenciasNaTela(chave);
  atualizarProgressoTestes();
}

function arquivosDoEvento(lista) {
  return Array.from(lista || []).map((it) => (it.kind === 'file' ? it.getAsFile() : it)).filter((f) => f && f.size !== undefined);
}

$('#md-plano').addEventListener('click', async (ev) => {
  const s = ev.target.closest('.cenario');
  if (!s) return;
  if (ev.target.closest('.cen-anexar')) { s.querySelector('.cen-arquivo').click(); return; }
  const rem = ev.target.closest('.evid-remover');
  if (!rem) return;
  if (!confirm('Remover a evidência ' + rem.dataset.nome + '?')) return;
  try {
    await api('/api/evidencias/remover', { chave: s.dataset.chave, nome: rem.dataset.nome });
    await carregarEvidencias();
    atualizarEvidenciasNaTela(s.dataset.chave);
    atualizarProgressoTestes();
  } catch (e) { avisar(e.message); }
});

$('#md-plano').addEventListener('change', (ev) => {
  if (!ev.target.classList.contains('cen-arquivo')) return;
  const s = ev.target.closest('.cenario');
  const arquivos = arquivosDoEvento(ev.target.files);
  ev.target.value = '';
  if (arquivos.length) enviarEvidencias(s.dataset.chave, arquivos);
});

// print colado (Win+Shift+S e Ctrl+V) com o foco na observacao ou no botao de anexar
$('#md-plano').addEventListener('paste', (ev) => {
  const s = ev.target.closest && ev.target.closest('.cenario');
  const arquivos = arquivosDoEvento(ev.clipboardData && ev.clipboardData.items);
  if (!s || !arquivos.length) return;
  ev.preventDefault();
  enviarEvidencias(s.dataset.chave, arquivos);
});

$('#md-plano').addEventListener('dragover', (ev) => {
  const s = ev.target.closest('.cenario');
  if (!s || !Array.from(ev.dataTransfer.types || []).includes('Files')) return;
  ev.preventDefault();
  $$('#md-plano .cenario.arrastando').forEach((x) => { if (x !== s) x.classList.remove('arrastando'); });
  s.classList.add('arrastando');
});
$('#md-plano').addEventListener('dragleave', (ev) => {
  const s = ev.target.closest('.cenario');
  if (s && !s.contains(ev.relatedTarget)) s.classList.remove('arrastando');
});
$('#md-plano').addEventListener('drop', (ev) => {
  const s = ev.target.closest('.cenario');
  if (!s) return;
  ev.preventDefault();
  s.classList.remove('arrastando');
  const arquivos = arquivosDoEvento(ev.dataTransfer.files);
  if (arquivos.length) enviarEvidencias(s.dataset.chave, arquivos);
});

function ajustarAlturaObs(ta) {
  ta.style.height = 'auto';
  ta.style.height = Math.min(ta.scrollHeight + 2, 200) + 'px';
}

async function salvarTeste(chave) {
  clearTimeout(timersTeste[chave]);
  delete timersTeste[chave];
  const s = document.querySelector('#md-plano .cenario[data-chave="' + chave + '"]');
  const t = testes[chave] || {};
  try {
    await api('/api/testes', { chave, titulo: s ? s.dataset.titulo : (t.titulo || ''), feito: !!t.feito, observacao: t.observacao || '' });
    if (s) {
      const ok = s.querySelector('.cen-salvo');
      ok.textContent = '✓ salvo';
      clearTimeout(ok.t);
      ok.t = setTimeout(() => { ok.textContent = ''; }, 2000);
    }
  } catch (e) { avisar('Não salvou o cenário: ' + e.message); }
}

async function salvarTestesPendentes() {
  await Promise.all(Object.keys(timersTeste).map((k) => salvarTeste(k)));
}

function atualizarProgressoTestes() {
  const lista = cenariosNaTela();
  const barra = $('#barra-testes');
  barra.hidden = lista.length === 0;
  if (!lista.length) return;
  const feitos = lista.filter((c) => c.feito).length;
  const obs = lista.filter((c) => c.observacao).length;
  const evid = lista.reduce((n, c) => n + c.evidencias, 0);
  $('#progresso-testes').textContent = feitos + ' de ' + lista.length + ' cenários feitos' +
    (obs ? ' · ' + obs + (obs === 1 ? ' observação' : ' observações') : '') +
    (evid ? ' · ' + evid + (evid === 1 ? ' evidência' : ' evidências') : '');
  const t = estado && estado.tarefa;
  $('#btn-enviar-testes').disabled = !(feitos + obs) || !estado.temSessao || !!(t && t.rodando);
}

$('#md-plano').addEventListener('change', (ev) => {
  if (!ev.target.classList.contains('cen-feito')) return;
  const s = ev.target.closest('.cenario');
  const chave = s.dataset.chave;
  testes[chave] = Object.assign({}, testes[chave], { titulo: s.dataset.titulo, feito: ev.target.checked });
  s.classList.toggle('feito', ev.target.checked);
  salvarTeste(chave);
  atualizarProgressoTestes();
});

$('#md-plano').addEventListener('input', (ev) => {
  if (!ev.target.classList.contains('cen-obs')) return;
  const s = ev.target.closest('.cenario');
  const chave = s.dataset.chave;
  testes[chave] = Object.assign({}, testes[chave], { titulo: s.dataset.titulo, observacao: ev.target.value });
  s.classList.toggle('com-obs', !!ev.target.value.trim());
  ajustarAlturaObs(ev.target);
  clearTimeout(timersTeste[chave]);
  timersTeste[chave] = setTimeout(() => salvarTeste(chave), 700);
  atualizarProgressoTestes();
});

$('#btn-enviar-testes').addEventListener('click', async () => {
  await salvarTestesPendentes();
  const lista = cenariosNaTela();
  const feitos = lista.filter((c) => c.feito).length;
  const linhas = lista.map((c) => c.titulo + ': ' + (c.feito ? 'feito' : 'NÃO feito') +
    (c.evidencias ? ' (' + c.evidencias + (c.evidencias === 1 ? ' evidência anexada' : ' evidências anexadas') + ')' : '') +
    (c.observacao ? ' — obs.: ' + c.observacao.replace(/\s+/g, ' ') : ''));
  const texto = 'Resultado dos meus testes do plano (' + feitos + ' de ' + lista.length + ' cenários feitos; também em out/' + estado.pasta +
    '/execucao-testes.json): ' + linhas.join(' | ') + '. Leve isso em conta para escrever o card, seguindo a etapa "Execução pelo dev" do fluxo.';
  if (!confirm('Enviar ao Kiro o resultado de ' + feitos + ' de ' + lista.length + ' cenários? Ele vai atualizar o plano (e a avaliação, se alguma observação indicar problema).')) return;
  try {
    await api('/api/responder', { texto });
    abrirAba('conversa');
    await atualizar();
  } catch (e) { avisar(e.message); }
});

function render() {
  if (estado.pasta !== pastaAtual) {
    pastaAtual = estado.pasta;
    Object.keys(cache).forEach((k) => delete cache[k]);
    chaveAbaRenderizada = '';
  }
  renderTopo();
  renderEtapas();
  renderConversa();
  renderPublicar();
  renderAbaArquivo();
  if (abaAtual === 'plano') atualizarProgressoTestes();
  acompanharRevisao();
  if (!estado.card && !dialogoAbertoUmaVez) { dialogoAbertoUmaVez = true; abrirDialogo(); }
}

function abrirAba(aba) {
  abaAtual = aba;
  $$('#abas button').forEach((b) => b.classList.toggle('ativa', b.dataset.aba === aba));
  $$('.painel').forEach((p) => { p.hidden = p.id !== 'painel-' + aba; });
  if (estado) renderAbaArquivo();
  if (aba === 'conversa') { const rol = $('#rolagem-conversa'); rol.scrollTop = rol.scrollHeight; }
  if (aba === 'aprendizado') { carregarPropostas(); carregarRevisao(); }
  if (aba === 'publicar') carregarColunas();
}

async function atualizar() {
  try {
    estado = await api('/api/estado');
    render();
  } catch (e) {
    const el = $('#status');
    el.textContent = 'Servidor fora do ar';
    el.className = 'status erro';
  }
}

// ---------------- dialogo "Novo card" ----------------

const dlg = $('#dlg-card');
const inBranch = $('#in-branch');
const inCard = $('#in-card');
const listaBranches = $('#lista-branches');
let branchEscolhida = '';
let previa = null;
let sugestoes = [];
let ativa = -1;
let timerBranch = null;
let timerCard = null;
let seqBases = 0;
let seqBranches = 0;

// A mesma janela serve ao fechamento ("card": branch do card + base) e a avaliacao tecnica
// ("avaliacao": so o card e a branch com o codigo atual do modulo, sem base).
let modoDialogo = 'card';

function prepararDialogo(modo) {
  const av = modo === 'avaliacao';
  if (modo !== modoDialogo) {
    // a branch de um modo nao serve para o outro
    inBranch.value = '';
    branchEscolhida = '';
    $('#bases').innerHTML = '<p class="dica">Escolha a branch para ver as bases.</p>';
  }
  modoDialogo = modo;
  $('#dlg-titulo').textContent = av ? 'Avaliação técnica' : 'Novo card';
  $('#rotulo-branch').textContent = av ? 'Código de referência: branch com o código atual do módulo' : 'Branch em que você trabalhou';
  $('#campo-base').hidden = av;
  $('#btn-comecar').textContent = av ? 'Começar avaliação' : 'Começar';
  const refs = $('#referencias');
  const sugestoes = (configApp.avaliacao && configApp.avaliacao.referencias) || [];
  refs.hidden = !av || !sugestoes.length;
  refs.innerHTML = av ? 'Sugestões: ' + sugestoes.map((r) => '<button type="button" class="chip-ref" data-ref="' + esc(r) + '">' + esc(r) + '</button>').join('') : '';
}

async function abrirDialogo() {
  $('#dlg-aviso').textContent = '';
  listaBranches.hidden = true;
  meusCards = null; // relista os cards a cada abertura (o servidor guarda por 60 s)
  if (!dlg.open) dlg.showModal();
  try {
    const r = await api('/api/repo');
    const dica = $('#dica-branch');
    if (modoDialogo === 'avaliacao') {
      dica.innerHTML = 'O agente lê o código desta branch, não a pasta do repositório. A Visita Técnica, por exemplo, não está no master: use a geral-merge.';
    } else {
      dica.innerHTML = 'Repositório <code>' + esc(r.repo) + '</code>' +
        (r.branchAtual ? ' · branch atual: <a href="#" id="usar-atual"><code>' + esc(r.branchAtual) + '</code></a>' : '');
      const link = $('#usar-atual');
      if (link) link.addEventListener('click', (ev) => { ev.preventDefault(); escolherBranch(r.branchAtual); });
      if (!inBranch.value && r.branchAtual && !/^(master|homologacao)$/.test(r.branchAtual)) escolherBranch(r.branchAtual, true);
    }
  } catch (e) {
    $('#dica-branch').textContent = e.message;
  }
  inCard.focus();
  atualizarComecar();
}

$('#referencias').addEventListener('click', (ev) => {
  const b = ev.target.closest('.chip-ref');
  if (b) escolherBranch(b.dataset.ref);
});

function fecharDialogo() { dlg.close(); }

async function buscarBranches() {
  const seq = ++seqBranches;
  try {
    const r = await api('/api/branches?q=' + encodeURIComponent(inBranch.value.trim()));
    if (seq !== seqBranches) return;
    sugestoes = r.branches || [];
    ativa = -1;
    listaBranches.innerHTML = sugestoes.length
      ? sugestoes.map((b, i) => '<li role="option" data-i="' + i + '"><div class="nome">' + esc(b.nome) + (b.local ? '<span class="etiqueta">local</span>' : '') +
        '</div><div class="detalhe">' + esc(b.data) + ' · ' + esc(b.autor) + ' · ' + esc(b.assunto) + '</div></li>').join('')
      : '<li class="sem-resultado"><div class="detalhe">Nenhuma branch com esse trecho.</div></li>';
    listaBranches.hidden = false;
    inBranch.setAttribute('aria-expanded', 'true');
  } catch (e) {
    avisar(e.message);
  }
}

function marcarAtiva(i) {
  const itens = $$('#lista-branches li[data-i]');
  if (!itens.length) return;
  ativa = (i + itens.length) % itens.length;
  itens.forEach((li, n) => li.classList.toggle('ativa', n === ativa));
  itens[ativa].scrollIntoView({ block: 'nearest' });
}

function esconderLista() {
  listaBranches.hidden = true;
  inBranch.setAttribute('aria-expanded', 'false');
}

// automatica = escolhida pela pagina (branch atual do repositorio ou achada pelo numero do
// card); escolher outro card troca uma branch automatica, mas nunca a que o dev escolheu.
let branchAutomatica = false;

function escolherBranch(nome, automatica) {
  nome = (nome || '').trim();
  if (!nome) return;
  inBranch.value = nome;
  branchEscolhida = nome;
  branchAutomatica = !!automatica;
  esconderLista();
  // na avaliacao a branch e so a referencia do codigo: nao diz o card nem tem base
  if (modoDialogo === 'avaliacao') { atualizarComecar(); return; }
  const m = nome.match(/card[_-]?(\d{2,6})/i) || nome.match(/(?:^|[\/_-])(\d{3,6})(?=[_-]|$)/);
  if (m && (!inCard.value.trim() || inCard.dataset.auto === '1')) {
    inCard.value = m[1];
    inCard.dataset.auto = '1';
    carregarPrevia();
  } else {
    if (!m && inCard.dataset.auto === '1') {
      // o card tinha vindo do nome da branch anterior
      inCard.value = '';
      inCard.dataset.auto = '0';
      previa = null;
      $('#previa-card').hidden = true;
    }
    carregarBases();
  }
  atualizarComecar();
}

inBranch.addEventListener('input', () => {
  branchEscolhida = '';
  $('#bases').innerHTML = '<p class="dica">Escolha a branch na lista para ver as bases.</p>';
  atualizarComecar();
  clearTimeout(timerBranch);
  timerBranch = setTimeout(buscarBranches, 220);
});
inBranch.addEventListener('focus', () => { if (!branchEscolhida) buscarBranches(); });
inBranch.addEventListener('keydown', (ev) => {
  if (ev.key === 'ArrowDown') { ev.preventDefault(); if (listaBranches.hidden) buscarBranches(); else marcarAtiva(ativa + 1); }
  else if (ev.key === 'ArrowUp') { ev.preventDefault(); marcarAtiva(ativa - 1); }
  else if (ev.key === 'Enter') {
    ev.preventDefault();
    if (!listaBranches.hidden && sugestoes.length) escolherBranch(sugestoes[ativa >= 0 ? ativa : 0].nome);
    else escolherBranch(inBranch.value);
  } else if (ev.key === 'Escape' && !listaBranches.hidden) { ev.preventDefault(); ev.stopPropagation(); esconderLista(); }
});
listaBranches.addEventListener('mousedown', (ev) => {
  const li = ev.target.closest('li[data-i]');
  if (li) { ev.preventDefault(); escolherBranch(sugestoes[Number(li.dataset.i)].nome); }
});
inBranch.addEventListener('blur', () => {
  setTimeout(() => {
    esconderLista();
    const v = inBranch.value.trim();
    if (!v || v === branchEscolhida) return;
    // So escolhe sozinho quando nao ha duvida: nome exato ou um unico resultado.
    const exata = sugestoes.find((b) => b.nome === v);
    if (exata) escolherBranch(exata.nome);
    else if (sugestoes.length === 1) escolherBranch(sugestoes[0].nome);
  }, 150);
});

inCard.addEventListener('input', () => {
  inCard.dataset.auto = '0';
  previa = null;
  clearTimeout(timerCard);
  timerCard = setTimeout(carregarPrevia, 450);
  mostrarMeusCards();
  atualizarComecar();
});

// ---- lista "meus cards" (abertos e atribuidos a mim, de qualquer projeto) ----

const listaCards = $('#lista-cards');
let meusCards = null;        // vem do GitLab uma vez por abertura da janela
let sugestoesCards = [];
let ativaCard = -1;

function semAcento(s) {
  return String(s || '').normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();
}

function esconderListaCards() {
  listaCards.hidden = true;
  inCard.setAttribute('aria-expanded', 'false');
}

async function mostrarMeusCards() {
  const v = inCard.value.trim();
  if (/^https?:/i.test(v)) { esconderListaCards(); return; }
  listaCards.hidden = false;
  inCard.setAttribute('aria-expanded', 'true');
  if (!meusCards) {
    listaCards.innerHTML = '<li class="sem-resultado"><div class="detalhe">Buscando os seus cards no GitLab…</div></li>';
    try {
      meusCards = (await api('/api/meus-cards')).cards || [];
    } catch (e) {
      listaCards.innerHTML = '<li class="sem-resultado"><div class="detalhe">Não consegui listar os seus cards: ' + esc(e.message) + '. Digite o número ou cole o link.</div></li>';
      return;
    }
  }
  // valor que veio do nome da branch nao filtra: mostra todos
  const termos = inCard.dataset.auto === '1' ? [] : semAcento(v).replace(/#/g, '').split(/\s+/).filter(Boolean);
  sugestoesCards = meusCards.filter((c) => {
    const alvo = semAcento(c.iid + ' ' + c.titulo + ' ' + c.projeto);
    return termos.every((t) => alvo.includes(t));
  });
  ativaCard = -1;
  if (!sugestoesCards.length) {
    listaCards.innerHTML = '<li class="sem-resultado"><div class="detalhe">' +
      (meusCards.length ? 'Nenhum card seu com esse trecho. Pode digitar o número ou colar o link de outro card.' : 'Nenhum card aberto atribuído a você. Digite o número ou cole o link.') +
      '</div></li>';
    return;
  }
  listaCards.innerHTML = '<li class="titulo-lista">Atribuídos a você (' + sugestoesCards.length + ')</li>' +
    sugestoesCards.map((c, i) => '<li role="option" data-i="' + i + '"><div class="nome-card"><strong>#' + c.iid + '</strong>' + esc(c.titulo) + '</div>' +
      '<div class="detalhe">' + esc(c.coluna || 'sem coluna do quadro') + ' · ' + esc(c.projeto) + ' · atualizado em ' + esc(c.atualizado) + '</div></li>').join('');
}

function marcarAtivaCard(i) {
  const itens = $$('#lista-cards li[data-i]');
  if (!itens.length) return;
  ativaCard = (i + itens.length) % itens.length;
  itens.forEach((li, n) => li.classList.toggle('ativa', n === ativaCard));
  itens[ativaCard].scrollIntoView({ block: 'nearest' });
}

function escolherCard(c) {
  inCard.value = c.valor;
  inCard.dataset.auto = '0';
  esconderListaCards();
  clearTimeout(timerCard);
  carregarPrevia();
  // na avaliacao o card ainda nao tem branch: a referencia e escolhida a parte
  if (modoDialogo === 'card' && (!branchEscolhida || branchAutomatica)) sugerirBranchDoCard(c.iid);
  atualizarComecar();
}

// Procura a branch com o numero do card no nome: uma so, escolhe; varias, abre a lista.
async function sugerirBranchDoCard(iid) {
  try {
    const r = await api('/api/branches?q=' + encodeURIComponent(iid));
    const bs = (r.branches || []).filter((b) => new RegExp('(^|[^0-9])' + iid + '([^0-9]|$)').test(b.nome));
    if (bs.length === 1) {
      escolherBranch(bs[0].nome, true);
      // pode haver outra branch do card sem o numero no nome (ex.: "...-evolucao")
      $('#dica-branch').textContent = 'Achei pela única branch com o #' + iid + ' no nome. Confira se foi nela que você trabalhou; se não, digite parte do nome da sua.';
    } else {
      branchEscolhida = '';
      branchAutomatica = false;
      inBranch.value = String(iid);
      $('#bases').innerHTML = '<p class="dica">Escolha a branch na lista para ver as bases.</p>';
      $('#dica-branch').textContent = bs.length
        ? bs.length + ' branches têm o #' + iid + ' no nome: escolha a sua.'
        : 'Nenhuma branch tem o #' + iid + ' no nome: digite parte do nome da sua.';
      if (bs.length) { inBranch.focus(); buscarBranches(); }
      atualizarComecar();
    }
  } catch (e) {
    avisar(e.message);
  }
}

inCard.addEventListener('focus', mostrarMeusCards);
inCard.addEventListener('keydown', (ev) => {
  if (ev.key === 'ArrowDown') { ev.preventDefault(); if (listaCards.hidden) mostrarMeusCards(); else marcarAtivaCard(ativaCard + 1); }
  else if (ev.key === 'ArrowUp') { ev.preventDefault(); marcarAtivaCard(ativaCard - 1); }
  else if (ev.key === 'Enter') {
    ev.preventDefault();
    if (!listaCards.hidden && ativaCard >= 0) escolherCard(sugestoesCards[ativaCard]);
    else if (!listaCards.hidden && sugestoesCards.length === 1) escolherCard(sugestoesCards[0]);
    else { esconderListaCards(); carregarPrevia(); }
  } else if (ev.key === 'Escape' && !listaCards.hidden) { ev.preventDefault(); ev.stopPropagation(); esconderListaCards(); }
});
listaCards.addEventListener('mousedown', (ev) => {
  const li = ev.target.closest('li[data-i]');
  if (li) { ev.preventDefault(); escolherCard(sugestoesCards[Number(li.dataset.i)]); }
});
inCard.addEventListener('blur', () => setTimeout(esconderListaCards, 150));

async function carregarPrevia() {
  const v = inCard.value.trim();
  const box = $('#previa-card');
  previa = null;
  if (!v) { box.hidden = true; atualizarComecar(); return; }
  box.hidden = false;
  box.className = 'previa';
  box.textContent = 'Buscando o card no GitLab…';
  try {
    const p = await api('/api/card?ref=' + encodeURIComponent(v));
    if (v !== inCard.value.trim()) return;
    previa = p;
    if (p.erro) {
      box.className = 'previa erro';
      box.textContent = '#' + p.iid + ': não consegui ler o card no GitLab (' + p.erro + '). Dá para começar mesmo assim.';
    } else {
      box.innerHTML = '<div class="titulo">#' + p.iid + ' · ' + esc(p.titulo) + '</div><div class="dica">' +
        esc(p.coluna || 'sem coluna do quadro') + ' · ' + (p.estado === 'closed' ? 'fechado' : 'aberto') +
        ' · <a href="' + esc(p.url) + '" target="_blank" rel="noopener">abrir no GitLab</a></div>';
    }
  } catch (e) {
    if (v !== inCard.value.trim()) return;
    box.className = 'previa erro';
    box.textContent = e.message;
  }
  if (branchEscolhida && modoDialogo === 'card') carregarBases();
  atualizarComecar();
}

function numeroDoCard() {
  if (previa && previa.iid) return previa.iid;
  const v = inCard.value.trim();
  const m = v.match(/^#?(\d+)$/) || v.match(/\/issues\/(\d+)/);
  return m ? m[1] : '';
}

function baseEscolhida() {
  const r = document.querySelector('input[name=base]:checked');
  if (!r) return '';
  return r.value === '__outra' ? $('#in-base-outra').value.trim() : r.value;
}

function plural(n, um, varios) {
  return Number(n).toLocaleString('pt-BR') + ' ' + (n === 1 ? um : varios);
}

async function carregarBases() {
  if (!branchEscolhida) return;
  const seq = ++seqBases;
  const el = $('#bases');
  const anterior = baseEscolhida();
  el.innerHTML = '<p class="dica">Contando os commits da branch em cada base…</p>';
  try {
    const r = await api('/api/bases?branch=' + encodeURIComponent(branchEscolhida) + '&iid=' + encodeURIComponent(numeroDoCard()));
    if (seq !== seqBases) return;
    const bases = r.bases || [];
    const zeradas = bases.filter((b) => b.tipo === 'branch' && b.commits === 0).map((b) => b.nome);
    const temCard = bases.some((b) => b.tipo === 'card');
    let aviso = '';
    if (zeradas.length && !temCard) {
      aviso = '<p class="aviso-base">A branch não tem commits fora de <code>' + esc(zeradas.join(', ')) + '</code>: ou ainda não há commit dela ' +
        '(só alterações locais, que não entram na análise), ou ela já foi mergeada. Se já foi mergeada, use <strong>Outra</strong> com o commit ' +
        'anterior ao primeiro commit do card (ex.: <code>abc1234~1</code>).</p>';
    }
    el.innerHTML = aviso + bases.map((b) => {
      let selo = '';
      let texto;
      if (b.contaminada) {
        selo = '<span class="selo ruim">contaminada</span>';
        texto = 'O diff traria ' + plural(b.commits, 'commit', 'commits') + ', com o merge do homologacao inteiro.';
      } else if (b.commits === 0) {
        selo = '<span class="selo neutro">já contém a branch</span>';
        texto = 'A branch já foi mergeada nela: o diff ficaria vazio.';
      } else {
        if (b.recomendada) selo = '<span class="selo ok">recomendada</span>';
        texto = plural(b.commits, 'commit', 'commits') + ' da branch fora dela.';
      }
      if (b.tipo === 'card') {
        texto = 'Último merge antes dos ' + plural(b.topo, 'commit', 'commits') + ' do topo da branch (' +
          b.citam + (b.citam === 1 ? ' cita' : ' citam') + ' o #' + numeroDoCard() + '). Use quando a branch já foi mergeada ou recebeu merge de outro card.';
      }
      const bloqueada = b.contaminada;
      return '<label class="opcao-base' + (bloqueada ? ' bloqueada' : '') + '"><input type="radio" name="base" value="' + esc(b.nome) + '"' + (bloqueada ? ' disabled' : '') + '>' +
        '<span class="opcao-texto"><strong>' + esc(b.nome) + selo + '</strong><small>' + esc(texto) + '</small></span></label>';
    }).join('') || '<p class="dica">Nenhuma base conhecida encontrada no repositório.</p>';
    const radios = $$('#bases input[name=base]');
    const manter = radios.find((x) => x.value === anterior && !x.disabled);
    const recomendada = bases.find((b) => b.recomendada);
    if (manter) manter.checked = true;
    else if (recomendada) radios.find((x) => x.value === recomendada.nome).checked = true;
  } catch (e) {
    if (seq !== seqBases) return;
    el.innerHTML = '<p class="dica" style="color:var(--perigo)">' + esc(e.message) + '</p>';
  }
  atualizarComecar();
}

$('#bases').addEventListener('change', atualizarComecar);
$('#in-base-outra').addEventListener('input', () => {
  document.querySelector('input[name=base][value=__outra]').checked = true;
  atualizarComecar();
});
document.querySelector('input[name=base][value=__outra]').addEventListener('change', () => { $('#in-base-outra').focus(); atualizarComecar(); });

function atualizarComecar() {
  const falta = [];
  if (!inCard.value.trim()) falta.push('o card');
  if (!branchEscolhida) falta.push(modoDialogo === 'avaliacao' ? 'a branch de referência' : 'a branch');
  if (modoDialogo === 'card' && !baseEscolhida()) falta.push('a base');
  $('#btn-comecar').disabled = falta.length > 0;
  $('#dlg-aviso').textContent = falta.length ? 'Falta escolher ' + falta.join(', ') + '.' : '';
}

$('#form-iniciar').addEventListener('submit', async (ev) => {
  ev.preventDefault();
  const av = modoDialogo === 'avaliacao';
  const base = av ? '' : baseEscolhida();
  if (!branchEscolhida || !inCard.value.trim() || (!av && !base)) { atualizarComecar(); return; }
  const oQue = av ? 'a avaliação técnica do card #' : 'o card #';
  if (estado && estado.card && !confirm('Começar ' + oQue + numeroDoCard() + '? O fluxo atual (#' + estado.iid + ') fica salvo em out/, mas sai da tela.')) return;
  $('#btn-comecar').disabled = true;
  try {
    const titulo = previa && !previa.erro ? previa.titulo : '';
    if (av) await api('/api/iniciar-avaliacao', { card: inCard.value.trim(), referencia: branchEscolhida, titulo });
    else await api('/api/iniciar', { card: inCard.value.trim(), branch: branchEscolhida, base, titulo });
    fecharDialogo();
    assinaturaConversa = '';
    ultimaSaidaCard = '';
    abrirAba('conversa');
    await atualizar();
  } catch (e) {
    avisar(e.message);
    atualizarComecar();
  }
});

$('#btn-novo').addEventListener('click', () => { prepararDialogo('card'); abrirDialogo(); });
$('#btn-avaliacao').addEventListener('click', () => { prepararDialogo('avaliacao'); abrirDialogo(); });
$('#btn-fechar-dlg').addEventListener('click', fecharDialogo);
$('#btn-dlg-cancelar').addEventListener('click', fecharDialogo);

// ---------------- conversa e acoes ----------------

const caixaResposta = $('#form-resposta textarea');

function ajustarAltura() {
  caixaResposta.style.height = 'auto';
  caixaResposta.style.height = Math.min(caixaResposta.scrollHeight + 2, 180) + 'px';
}

async function enviarResposta() {
  // com o painel de perguntas aberto e algo marcado, vai tudo junto
  if (!$('#painel-perguntas').hidden && temRespostaNoPainel()) { await enviarRespostasPerguntas(); return; }
  const texto = caixaResposta.value.trim();
  if (!texto) return;
  try {
    await api('/api/responder', { texto });
    caixaResposta.value = '';
    ajustarAltura();
    await atualizar();
  } catch (e) { avisar(e.message); }
}
$('#form-resposta').addEventListener('submit', (ev) => { ev.preventDefault(); enviarResposta(); });
caixaResposta.addEventListener('input', ajustarAltura);
caixaResposta.addEventListener('keydown', (ev) => {
  if (ev.key === 'Enter' && ev.ctrlKey) { ev.preventDefault(); enviarResposta(); }
});
$$('#atalhos .chip').forEach((b) => b.addEventListener('click', () => {
  caixaResposta.value = b.textContent;
  ajustarAltura();
  caixaResposta.focus();
}));

$('#btn-cancelar').addEventListener('click', async () => {
  if (!confirm('Cancelar o que o Kiro está fazendo?')) return;
  try { await api('/api/cancelar', {}); await atualizar(); } catch (e) { avisar(e.message); }
});

$('#abas').addEventListener('click', (ev) => {
  const b = ev.target.closest('button[data-aba]');
  if (b) abrirAba(b.dataset.aba);
});

$('#form-publicar').addEventListener('change', () => { if (estado) renderPublicar(); });

$('#btn-simular').addEventListener('click', async () => {
  try {
    ultimaSaidaCard = '(rodando…)';
    await api('/api/simular', opcoesPublicar());
    await atualizar();
  } catch (e) { avisar(e.message); }
});

$('#btn-publicar').addEventListener('click', async () => {
  const o = opcoesPublicar();
  const partes = emAvaliacao()
    ? ['pôr a etiqueta de pontos no card #' + estado.iid, o.semFilho ? 'gravar a avaliação como nota interna no card filho existente (ou no pai, se não houver filho)' : 'criar ou concluir o card filho "Avaliação Técnica" com a avaliação como nota interna nele']
    : ['comentar o plano de teste no card #' + estado.iid];
  if (!o.semFilho && !emAvaliacao()) partes.push('criar ou concluir o card filho');
  if (o.coluna) partes.push('mover o card para "' + o.coluna + '"');
  if (!confirm('Isto grava no GitLab, no seu nome: ' + partes.join(', ') + '.\n\nConfira a saída do Simular antes. Publicar agora?')) return;
  try {
    await api('/api/publicar', Object.assign({ confirmo: true }, o));
    await atualizar();
  } catch (e) { avisar(e.message); }
});

// ---------------- previa do comentario ----------------

let textoPrevia = '';

// Cada artigo da previa (comentario e nota interna) mostra o texto que vai para o card:
// o editado pelo dev, se houver, senao o gerado no Simular. "Editar" abre o markdown;
// "Salvar" grava a versao do dev (/api/texto) e o Publicar passa a usar essa versao.
const infoTextos = {};      // nome do texto -> { gerado, editado, desatualizado }

function semMarcador(t) { return String(t || '').replace(/<!--[\s\S]*?-->/g, '').trim(); }

function renderArtigo(artigo) {
  const info = infoTextos[artigo.dataset.nome] || {};
  const texto = info.editado || info.gerado || '';
  mdSemSelos = true;
  try { artigo.querySelector('.gl-md').innerHTML = md(semMarcador(texto)); } finally { mdSemSelos = false; }
  artigo.querySelectorAll('.gl-md a').forEach((l) => { l.target = '_blank'; l.rel = 'noopener'; });
  artigo.querySelector('.selo-editado').hidden = !info.editado;
  artigo.querySelector('.btn-descartar-edicao').hidden = !info.editado;
  const aviso = artigo.querySelector('.aviso-edicao');
  aviso.hidden = !info.desatualizado;
  aviso.textContent = info.desatualizado
    ? 'O texto gerado mudou depois da sua edição (o plano ou a decisão mudaram). Revise e salve de novo, ou volte ao texto gerado: até lá o Publicar não grava.'
    : '';
  artigo.querySelector('.gl-md').hidden = false;
  artigo.querySelector('.nota-editor').hidden = true;
  artigo.querySelector('.btn-editar').hidden = false;
  if (artigo.id === 'previa-comentario' || artigo.dataset.nome === 'nota-avaliacao') textoPrevia = texto;
}

async function carregarArtigo(artigo, nome) {
  artigo.dataset.nome = nome;
  infoTextos[nome] = await api('/api/texto?nome=' + encodeURIComponent(nome));
  renderArtigo(artigo);
  return infoTextos[nome];
}

$('#dlg-previa').addEventListener('click', async (ev) => {
  const artigo = ev.target.closest('.nota-editavel');
  if (!artigo) return;
  const nome = artigo.dataset.nome;
  const info = infoTextos[nome] || {};
  const ta = artigo.querySelector('.nota-editor textarea');
  try {
    if (ev.target.closest('.btn-editar')) {
      ta.value = semMarcador(info.editado || info.gerado);
      artigo.querySelector('.gl-md').hidden = true;
      artigo.querySelector('.nota-editor').hidden = false;
      ev.target.closest('.btn-editar').hidden = true;
      ta.style.height = Math.min(Math.max(ta.scrollHeight + 4, 260), 560) + 'px';
      ta.focus();
    } else if (ev.target.closest('.btn-cancelar-edicao')) {
      renderArtigo(artigo);
    } else if (ev.target.closest('.btn-salvar-edicao')) {
      infoTextos[nome] = await api('/api/texto', { nome, texto: ta.value });
      renderArtigo(artigo);
      $('#previa-copiado').textContent = 'Salvo: o Publicar vai usar o seu texto.';
      await atualizar();
    } else if (ev.target.closest('.btn-descartar-edicao')) {
      if (!confirm('Descartar a sua edição e voltar ao texto gerado pelo agente?')) return;
      infoTextos[nome] = await api('/api/texto/descartar', { nome });
      renderArtigo(artigo);
      $('#previa-copiado').textContent = 'Voltou ao texto gerado.';
      await atualizar();
    }
  } catch (e) { avisar(e.message); }
});

// Avaliacao tecnica: so a nota interna, gravada no card filho "Avaliação Técnica".
async function abrirPreviaAvaliacao() {
  const a = estado.arquivos || {};
  if (!a['nota-avaliacao.md']) { avisar('Rode o Simular para gerar a nota interna.'); return; }
  $('#previa-titulo').textContent = 'Pré-visualização da nota interna';
  $('#previa-comentario').hidden = true;
  $('#previa-nota-banco').hidden = false;
  try { await carregarArtigo($('#previa-nota-banco'), 'nota-avaliacao'); } catch (e) { avisar(e.message); return; }
  const mudou = invalidamSimular().some((n) => (a[n] || '') > a['nota-avaliacao.md']);
  const aviso = $('#previa-aviso');
  aviso.className = 'previa-aviso' + (mudou ? ' desatualizada' : '');
  aviso.textContent = mudou
    ? 'A avaliação ou a decisão mudaram depois do último Simular. Esta é a versão antiga: rode o Simular de novo para ver a atual.'
    : 'Este é o texto exato que o Publicar vai gravar como nota interna no card filho "Avaliação Técnica" do #' + estado.iid + ', gerado no último Simular.';
  $('#previa-copiado').textContent = '';
  $('#dlg-previa').showModal();
  $('#dlg-previa .dialogo-corpo').scrollTop = 0;
}

async function abrirPrevia() {
  if (emAvaliacao()) { await abrirPreviaAvaliacao(); return; }
  $('#previa-titulo').textContent = 'Pré-visualização do comentário';
  $('#previa-comentario').hidden = false;
  const a = estado.arquivos || {};
  if (!a['comentario-plano.md']) { avisar('Rode o Simular para gerar o comentário.'); return; }
  // o GitLab nao mostra comentario HTML (o marcador <!-- card-sigcon:plano -->): semMarcador
  try { await carregarArtigo($('#previa-comentario'), 'comentario-plano'); } catch (e) { avisar(e.message); return; }
  const gerado = a['comentario-plano.md'];
  const mudou = invalidamSimular().some((n) => (a[n] || '') > gerado);
  // nota interna com o SQL do banco (so quando o Simular gerou)
  const temNota = !!(a['nota-banco.md'] && a['nota-banco.md'] >= gerado);
  $('#previa-nota-banco').hidden = !temNota;
  if (temNota) { try { await carregarArtigo($('#previa-nota-banco'), 'nota-banco'); } catch (e) { avisar(e.message); } }
  const aviso = $('#previa-aviso');
  aviso.className = 'previa-aviso' + (mudou ? ' desatualizada' : '');
  aviso.textContent = mudou
    ? 'O plano, a execução dos testes, as evidências, o SQL do banco ou a decisão mudaram depois do último Simular. Esta é a versão antiga: rode o Simular de novo para ver a atual.'
    : 'Este é o texto exato que o Publicar vai comentar no card, gerado no último Simular.';
  $('#previa-meta').textContent = 'comentaria no card #' + estado.iid;
  $('#previa-copiado').textContent = '';
  $('#dlg-previa').showModal();
  $('#dlg-previa .dialogo-corpo').scrollTop = 0;
}

$('#btn-previa').addEventListener('click', abrirPrevia);
$('#btn-fechar-previa').addEventListener('click', () => $('#dlg-previa').close());
$('#btn-previa-ok').addEventListener('click', () => $('#dlg-previa').close());
$('#dlg-previa').addEventListener('click', (ev) => { if (ev.target === ev.currentTarget) ev.currentTarget.close(); });
// copia pela selecao de texto quando o navegador nega a API da area de transferencia
function copiarPorSelecao(texto) {
  const ta = document.createElement('textarea');
  ta.value = texto;
  ta.setAttribute('readonly', '');
  ta.style.position = 'fixed';
  ta.style.opacity = '0';
  $('#dlg-previa').appendChild(ta);
  ta.select();
  let ok = false;
  try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
  ta.remove();
  return ok;
}

$('#btn-previa-copiar').addEventListener('click', async () => {
  let ok = false;
  try { await navigator.clipboard.writeText(textoPrevia); ok = true; } catch (e) { ok = copiarPorSelecao(textoPrevia); }
  $('#previa-copiado').textContent = ok ? 'Markdown copiado.' : 'O navegador bloqueou a cópia. O texto está em out/<card>/comentario-plano.md.';
});

// ---------------- aprendizado ----------------

let propostas = [];
let totalPropostasVisto = -1;

async function carregarPropostas() {
  const el = $('#lista-propostas');
  try {
    const r = await api('/api/propostas');
    propostas = r.propostas || [];
    totalPropostasVisto = propostas.length;
    $('#rotulo-todas').hidden = propostas.length < 2;
    $('#acoes-propostas').hidden = propostas.length === 0;
    $('#marcar-todas').checked = false;
    el.innerHTML = propostas.length
      // proposta com problema continua marcavel: da para descartar; o Gravar recusa e diz qual
      ? propostas.map((p) => '<label class="proposta' + (p.tipo === 'remover' ? ' remover' : '') + (p.problema ? ' com-problema' : '') + '">' +
          '<input type="checkbox" value="' + p.n + '">' +
          '<div class="proposta-corpo"><div class="proposta-topo">' +
          (p.tipo === 'remover' ? '<span class="selo ruim">remover</span>' : (p.tipo === 'adicionar' ? '' : '<span class="selo ruim">' + esc(p.tipo) + '</span>')) +
          '<span class="selo neutro">' + esc(p.area || 'sem área') + '</span>' +
          '<span>' + [p.card, p.data].filter(Boolean).map(esc).join(' · ') + '</span></div>' +
          '<p class="regra">' + inline(p.regra) + '</p>' +
          (p.porque ? '<p class="detalhe-proposta"><strong>Por quê:</strong> ' + inline(p.porque) + '</p>' : '') +
          (p.evidencia ? '<p class="detalhe-proposta"><strong>Evidência:</strong> ' + inline(p.evidencia) + '</p>' : '') +
          (p.problema ? '<p class="problema-proposta">Não dá para gravar: ' + esc(p.problema) + '. Corrija a proposta ou descarte.</p>' : '') +
          '</div></label>').join('')
      : '<p class="vazio-arquivo">Nenhuma proposta pendente. O agente propõe regras no fim de cada card.</p>';
  } catch (e) {
    el.innerHTML = '<p class="dica" style="color:var(--perigo)">' + esc(e.message) + '</p>';
  }
  atualizarBotoesPropostas();
}

function propostasMarcadas() {
  return $$('#lista-propostas input[type=checkbox]:checked').map((c) => {
    const p = propostas.find((x) => String(x.n) === c.value);
    return { n: p.n, regra: p.regra };
  });
}

function atualizarBotoesPropostas() {
  const n = propostasMarcadas().length;
  const sufixo = n ? ' ' + n + (n === 1 ? ' marcada' : ' marcadas') : ' marcadas';
  $('#btn-gravar-propostas').disabled = n === 0;
  $('#btn-descartar-propostas').disabled = n === 0;
  $('#btn-gravar-propostas').textContent = 'Gravar' + sufixo;
  $('#btn-descartar-propostas').textContent = 'Descartar' + sufixo;
}

async function aplicarPropostas(acao) {
  const lista = propostasMarcadas();
  if (!lista.length) return;
  if (acao === 'descartar' && !confirm('Descartar ' + lista.length + (lista.length === 1 ? ' proposta' : ' propostas') + '? Elas saem do arquivo de propostas e não entram nas regras.')) return;
  try {
    const r = await api('/api/aprender', acao === 'gravar' ? { aceitar: lista, descartar: [] } : { aceitar: [], descartar: lista });
    const avisos = String(r.saida || '').split('\n').filter((l) => /^(AVISO|ERRO)/.test(l)).join(' ');
    $('#resultado-propostas').textContent = r.codigo === 0
      ? (acao === 'gravar' ? 'Gravadas nas regras do time.' : 'Descartadas.') + (avisos ? ' ' + avisos : '')
      : (avisos || r.saida || 'Não consegui aplicar.');
    await carregarPropostas();
  } catch (e) { avisar(e.message); }
}

$('#lista-propostas').addEventListener('change', atualizarBotoesPropostas);
$('#marcar-todas').addEventListener('change', (ev) => {
  $$('#lista-propostas input[type=checkbox]:not(:disabled)').forEach((c) => { c.checked = ev.target.checked; });
  atualizarBotoesPropostas();
});
$('#btn-gravar-propostas').addEventListener('click', () => aplicarPropostas('gravar'));
$('#btn-descartar-propostas').addEventListener('click', () => aplicarPropostas('descartar'));

// ---------------- revisao do aprendizado ----------------
// Turno do Kiro em conversa propria (servidor: /api/revisao). O estado geral traz so
// se esta rodando; o texto vem do /api/revisao enquanto a aba esta aberta.

let revisaoRodava = false;

function dataHora(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  return isNaN(d) ? iso : d.toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
}

function renderRevisao(r, comTexto) {
  const rodando = !!(r && r.rodando);
  $('#btn-revisao').disabled = rodando;
  $('#btn-revisao').textContent = rodando ? 'Revisando…' : 'Pedir revisão ao Kiro';
  $('#btn-cancelar-revisao').hidden = !rodando;
  let st = 'Nenhuma revisão pedida ainda.';
  if (rodando) st = 'Revisão em andamento desde ' + hora(r.inicio) + '. Pode continuar usando a página; as propostas aparecem acima quando terminar.';
  else if (r) st = 'Última revisão: ' + dataHora(r.fim) + (typeof r.creditos === 'number' ? ' · ' + fmtCreditos(r.creditos) : '') + (r.codigo === 0 ? '.' : (r.codigo === -2 ? ' (cancelada).' : ' (terminou com erro).'));
  $('#status-revisao').textContent = st;
  if (comTexto && r && typeof r.texto === 'string') {
    const el = $('#resultado-revisao');
    el.hidden = !r.texto.trim();
    el.innerHTML = mensagemAgente(r.texto, rodando);
  }
}

async function carregarRevisao() {
  try {
    renderRevisao((await api('/api/revisao')).revisao, true);
  } catch (e) { $('#status-revisao').textContent = e.message; }
}

// chamado a cada atualizacao do estado
function acompanharRevisao() {
  const r = estado.revisao;
  const rodando = !!(r && r.rodando);
  const terminou = revisaoRodava && !rodando;
  revisaoRodava = rodando;
  if (abaAtual !== 'aprendizado') return;
  if (rodando || terminou) carregarRevisao(); else renderRevisao(r, false);
  if (terminou) carregarPropostas();
}

$('#btn-revisao').addEventListener('click', async () => {
  try {
    await api('/api/revisao', {});
    revisaoRodava = true;
    await carregarRevisao();
  } catch (e) { avisar(e.message); }
});
$('#btn-cancelar-revisao').addEventListener('click', async () => {
  if (!confirm('Cancelar a revisão do aprendizado?')) return;
  try {
    await api('/api/revisao/cancelar', {});
    await carregarRevisao();
  } catch (e) { avisar(e.message); }
});

// ---------------- wiki do sistema (copia local para o agente) ----------------

async function carregarWiki() {
  try {
    const r = await api('/api/wiki');
    $('#wiki-status').textContent = r.paginas
      ? r.paginas + ' páginas · cópia de ' + dataHora(r.atualizadaEm)
      : 'Ainda não baixada. O coletar baixa sozinho, ou clique abaixo.';
  } catch (e) { $('#wiki-status').textContent = e.message; }
}

$('#btn-wiki').addEventListener('click', async () => {
  const b = $('#btn-wiki');
  b.disabled = true;
  b.textContent = 'Atualizando…';
  try {
    const r = await api('/api/wiki/atualizar', {});
    if (r.codigo !== 0) {
      const erros = String(r.saida || '').split('\n').filter((l) => /^(ERRO|AVISO)/.test(l)).join(' ');
      avisar(erros || 'Não consegui atualizar a wiki.');
    }
  } catch (e) { avisar(e.message); }
  b.disabled = false;
  b.textContent = 'Atualizar wiki';
  carregarWiki();
});

// ---------------- inicio ----------------

(async function iniciar() {
  try {
    const config = await api('/api/config');
    configApp = config;
    // o que falta nesta maquina (servidor verifica ao abrir): token, repositorio, Kiro...
    const avisos = config.avisos || [];
    const faixa = $('#avisos-instalacao');
    faixa.hidden = !avisos.length;
    faixa.innerHTML = avisos.length
      ? '<strong>Falta configurar nesta máquina:</strong><ul>' + avisos.map((a) => '<li><strong>' + esc(a.nome) + '</strong> (' + esc(a.detalhe) + '): ' + esc(a.como) + '</li>').join('') +
        '</ul><span class="dica">Depois de corrigir, feche e abra o card-ui.cmd. No terminal, <code>card.cmd verificar</code> mostra o mesmo.</span>'
      : '';
    const sel = $('#form-publicar').atividade;
    (config.atividades || []).forEach((a) => {
      const o = document.createElement('option');
      o.value = a;
      o.textContent = a;
      sel.appendChild(o);
    });
  } catch (e) { /* segue sem a lista */ }
  carregarWiki();
  await atualizar();
  setInterval(atualizar, 2000);
})();
